#!/usr/bin/env python3
"""
Scale the Red Hat ranch workers by stopping and starting EC2 instances.

Workers with the tag `TestingFarmScaler=managed` are the pool. A worker with no allocations is stopped, not
terminated. When the queue needs more capacity, ineligible workers are made eligible first, then stopped
workers are started. `/data` on a worker is rebuilt on boot, see `ansible/files/tf-instance-store-init.sh`.

The loop touches only the workers it made ineligible itself, it records their nodes in `state.json`. A worker
made ineligible by a person, or by the `disable` command, is left alone until `enable` or `start`. A worker stopped
by the `stop` command is held in `state.json`, the loop does not start it until `start` or `enable`.
A running worker that lost its Nomad node is reported as unreachable and never stopped by the loop.

Needs Python 3.9, `boto3` and `python-nomad`. It replaces `testing-farm-worker-cleanup.py`.

Examples:

    redhat_worker_scaler.py status
    redhat_worker_scaler.py once --dry-run
    redhat_worker_scaler.py run
    redhat_worker_scaler.py pause && redhat_worker_scaler.py start-all --wait   # before a release
"""
import argparse
import bisect
import contextlib
import fcntl
import json
import logging
import math
import os
import sys
import time
from datetime import datetime, timezone

import boto3
import nomad
from botocore.exceptions import ClientError

LOGGER = logging.getLogger('worker-scaler')

TAG_KEY = 'TestingFarmScaler'
TAG_VALUE = 'managed'
INSTANCE_ID_ATTRIBUTE = 'unique.platform.aws.instance-id'

# worker classes
STOPPED = 'stopped'
STOPPING = 'stopping'
BOOTING = 'booting'
ACTIVE = 'active'
DRAINING = 'draining'
IDLE = 'idle'
# ineligible, but not by the loop
MANUAL = 'manual'
# running for a while, its Nomad node is not ready
UNREACHABLE = 'unreachable'

DEFAULT_NODE_MEM_MB = 61264

# Nomad marks the node of a stopped worker down shortly after the stop, a status change later than this after
# the start means the worker had a node during this boot.
NODE_DOWN_GRACE = 120


class Worker:
    def __init__(self, instance):
        self.instance = instance
        self.instance_id = instance['InstanceId']
        self.name = next((t['Value'] for t in instance.get('Tags', []) if t['Key'] == 'Name'), self.instance_id)
        self.ec2_state = instance['State']['Name']
        self.launch_time = instance.get('LaunchTime')
        self.node = None
        self.allocs = []
        self.used_mb = 0
        self.klass = None

    @property
    def node_mem_mb(self):
        return node_memory(self.node) if self.node else DEFAULT_NODE_MEM_MB

    @property
    def free_mb(self):
        return self.node_mem_mb - self.used_mb

    @property
    def eligible(self):
        return bool(self.node) and self.node.get('SchedulingEligibility') == 'eligible'

    def age(self):
        """Seconds since the instance was (re)started."""
        return (datetime.now(timezone.utc) - self.launch_time).total_seconds() if self.launch_time else 0


def node_memory(node):
    memory = node['NodeResources']['Memory']['MemoryMB']
    reserved = (node.get('ReservedResources') or {}).get('Memory', {}).get('MemoryMB', 0)
    return memory - reserved


def alloc_memory(alloc):
    allocated = alloc.get('AllocatedResources')
    if allocated:
        tasks = sum(t['Memory']['MemoryMB'] for t in allocated.get('Tasks', {}).values())
        return tasks + (allocated.get('Shared') or {}).get('MemoryMB', 0)
    return (alloc.get('Resources') or {}).get('MemoryMB', 0)


def group_memory(group):
    return sum((task.get('Resources') or {}).get('MemoryMB', 0) for task in group['Tasks'])


def pack(demand, capacities, node_mem=0):
    """
    Place the queued allocations on the free memory of the workers, largest first, each on the worker with the
    least free memory it fits on. Free memory of different workers cannot be combined, an allocation needs one
    worker. With `node_mem`, an allocation that fits nowhere goes to an empty worker.

    Returns the count of empty workers used and the allocations left over.
    """
    free = sorted(capacities)
    opened = 0
    left = []
    for size in sorted(demand, reverse=True):
        i = bisect.bisect_left(free, size)
        if i < len(free):
            rest = free.pop(i) - size
        elif size <= node_mem:
            rest = node_mem - size
            opened += 1
        else:
            left.append(size)
            continue
        bisect.insort(free, rest)
    return opened, left


class Scaler:
    def __init__(self, args):
        self.args = args
        self.dry_run = getattr(args, 'dry_run', False)
        session = boto3.Session(profile_name=args.profile, region_name=args.region)
        self.ec2 = session.client('ec2')
        self.nomad = nomad.Nomad(host=args.nomad_host, port=args.nomad_port, timeout=30)
        self.parent_memory = {}
        # the state of the current tick, None outside the loop
        self.state = None
        # IDs of all nodes known to Nomad, set by `inventory()`
        self.node_ids = set()
        # nesting depth of `locked()` in this process
        self._lock_depth = 0
        os.makedirs(args.state_dir, exist_ok=True)

    # state

    @property
    def _pause_file(self):
        return os.path.join(self.args.state_dir, 'paused')

    @property
    def _state_file(self):
        return os.path.join(self.args.state_dir, 'state.json')

    def paused(self):
        return os.path.exists(self._pause_file)

    def set_paused(self, paused):
        if paused:
            open(self._pause_file, 'w').close()
        elif self.paused():
            os.remove(self._pause_file)

    def load_state(self):
        try:
            with open(self._state_file) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def save_state(self, state):
        tmp = self._state_file + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(state, f)
        os.replace(tmp, self._state_file)

    @contextlib.contextmanager
    def locked(self):
        """Serialize the state changes of the loop and of the commands, nested calls in the process do not wait."""
        if self._lock_depth:
            self._lock_depth += 1
            try:
                yield
            finally:
                self._lock_depth -= 1
            return
        with open(os.path.join(self.args.state_dir, 'lock'), 'w') as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            self._lock_depth += 1
            try:
                yield
            finally:
                self._lock_depth -= 1

    def update_state(self, workers, hold=None):
        """
        A person changed the eligibility of the workers, the loop must not touch their nodes. `hold` True also keeps
        the loop from starting them, False lifts that.
        """
        if self.dry_run:
            return
        node_ids = {w.node['ID'] for w in workers if w.node}
        instance_ids = {w.instance_id for w in workers}
        with self.locked():
            state = self.load_state()
            state['disabled'] = [i for i in state.get('disabled', []) if i not in node_ids]
            if hold is not None:
                held = set(state.get('held', []))
                state['held'] = sorted((held | instance_ids) if hold else (held - instance_ids))
            self.save_state(state)

    # AWS

    def describe(self, managed=True):
        filters = [
            {'Name': 'tag:ServiceComponent', 'Values': ['Worker']},
            {'Name': 'tag:ServicePhase', 'Values': ['Prod']},
            {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'stopping', 'stopped']},
        ]
        if managed:
            filters.append({'Name': f'tag:{TAG_KEY}', 'Values': [TAG_VALUE]})

        instances = []
        for page in self.ec2.get_paginator('describe_instances').paginate(Filters=filters):
            for reservation in page['Reservations']:
                instances.extend(reservation['Instances'])
        return instances

    def start_instance(self, worker):
        self._log_action(f'start {worker.name} ({worker.instance_id})')
        if self.dry_run:
            return True
        try:
            self.ec2.start_instances(InstanceIds=[worker.instance_id])
        except ClientError as exc:
            LOGGER.error('cannot start %s: %s', worker.name, exc)
            return False
        return True

    def stop_instance(self, worker):
        self._log_action(f'stop {worker.name} ({worker.instance_id})')
        if self.dry_run:
            return
        try:
            self.ec2.stop_instances(InstanceIds=[worker.instance_id])
        except ClientError as exc:
            LOGGER.error('cannot stop %s: %s', worker.name, exc)

    # Nomad

    def set_eligibility(self, worker, eligible):
        self._log_action(f'{"enable" if eligible else "disable"} {worker.name}')
        if self.dry_run:
            return
        node_id = worker.node['ID']
        # recorded before the call, if the call fails the node stays eligible and is ACTIVE
        if self.state is not None and not eligible:
            self.state['disabled'] = sorted(set(self.state.get('disabled', [])) | {node_id})
            self.save_state(self.state)
        if eligible:
            self.nomad.node.eligible_node(node_id, eligible=True)
        else:
            self.nomad.node.eligible_node(node_id, ineligible=True)
        worker.node['SchedulingEligibility'] = 'eligible' if eligible else 'ineligible'
        # forgotten after the call, if the call fails the node stays recorded and ineligible
        if self.state is not None and eligible:
            self.state['disabled'] = sorted(set(self.state.get('disabled', [])) - {node_id})
            self.save_state(self.state)

    def active_allocs(self, node_id):
        allocs = self.nomad.node.get_allocations(node_id)
        return [a for a in allocs if a['ClientStatus'] in ('pending', 'running')]

    def queued_demand(self):
        """Memory of each allocation waiting for placement."""
        # a parent job can be registered again with other resources, do not keep its memory across calls
        self.parent_memory = {}
        demand = []
        for job in self.nomad.jobs.get_jobs():
            parent_id = job.get('ParentID')
            if not parent_id or job.get('Status') == 'dead':
                continue
            for group, summary in ((job.get('JobSummary') or {}).get('Summary') or {}).items():
                memory = self._parent_group_memory(parent_id, group) if summary.get('Queued') else 0
                if memory:
                    demand.extend([memory] * summary['Queued'])
        return demand

    def queued_mb(self):
        """Memory needed by the allocations waiting for placement."""
        return sum(self.queued_demand())

    def fits(self, demand, capacities):
        """The queued allocations fit on the free memory of the workers, with `headroom_mb` to spare."""
        _, left = pack(demand, capacities)
        return not left and sum(capacities) - sum(demand) >= self.args.headroom_mb

    def _parent_group_memory(self, parent_id, group):
        if parent_id not in self.parent_memory:
            parent = self.nomad.job.get_job(parent_id)
            self.parent_memory[parent_id] = {g['Name']: group_memory(g) for g in parent['TaskGroups']}
        return self.parent_memory[parent_id].get(group, 0)

    # inventory

    def inventory(self, disabled=frozenset(), managed=True, held=frozenset()):
        """
        Classify the workers. `disabled` holds the nodes the loop made ineligible, other ineligible nodes are
        `MANUAL`. `held` holds the instances stopped by the `stop` command, they are `MANUAL` too.
        """
        workers = [Worker(i) for i in self.describe(managed)]

        ready = {}
        # the newest status change of a node that is not ready, per instance
        not_ready = {}
        self.node_ids = set()
        for stub in self.nomad.nodes.get_nodes():
            self.node_ids.add(stub['ID'])
            node = self.nomad.node.get_node(stub['ID'])
            instance_id = node.get('Attributes', {}).get(INSTANCE_ID_ATTRIBUTE)
            if not instance_id:
                continue
            if node['Status'] != 'ready':
                not_ready[instance_id] = max(not_ready.get(instance_id, 0), node.get('StatusUpdatedAt') or 0)
            # a worker started again registers as a new node, prefer the newest one
            elif instance_id not in ready or node['CreateIndex'] > ready[instance_id]['CreateIndex']:
                ready[instance_id] = node

        for worker in workers:
            worker.node = ready.get(worker.instance_id)
            if worker.instance_id in held:
                # the loop leaves it alone until `start` or `enable`
                if worker.node:
                    worker.allocs = self.active_allocs(worker.node['ID'])
                    worker.used_mb = sum(alloc_memory(a) for a in worker.allocs)
                worker.klass = MANUAL
            elif worker.ec2_state == 'stopped':
                worker.klass = STOPPED
            elif worker.ec2_state == 'stopping':
                worker.klass = STOPPING
            elif worker.ec2_state == 'pending':
                worker.klass = BOOTING
            elif not worker.node:
                # A node of this instance changed status well after the start, the worker was up during this boot
                # and lost its node, e.g. a Nomad restart. It may still run tests, do not treat it as booting.
                launched = worker.launch_time.timestamp() if worker.launch_time else 0
                lost = not_ready.get(worker.instance_id, 0) > launched + NODE_DOWN_GRACE
                worker.klass = UNREACHABLE if lost else BOOTING
            else:
                worker.allocs = self.active_allocs(worker.node['ID'])
                worker.used_mb = sum(alloc_memory(a) for a in worker.allocs)
                if worker.eligible:
                    worker.klass = ACTIVE
                elif worker.node['ID'] in disabled:
                    worker.klass = DRAINING if worker.allocs else IDLE
                else:
                    worker.klass = MANUAL
        return workers

    # the loop

    def tick(self):
        args = self.args
        now = time.time()
        state = self.load_state()
        workers = self.inventory(set(state.get('disabled', [])), held=set(state.get('held', [])))
        # nodes gone from Nomad, e.g. collected after a stop, and nodes eligible again, e.g. a failed disable
        eligible = {w.node['ID'] for w in workers if w.eligible}
        state['disabled'] = sorted((set(state.get('disabled', [])) & self.node_ids) - eligible)
        # instances gone, e.g. terminated
        state['held'] = sorted(set(state.get('held', [])) & {w.instance_id for w in workers})
        self.state = state
        demand = self.queued_demand()
        queued = sum(demand)
        node_mem = max((w.node_mem_mb for w in workers if w.node), default=DEFAULT_NODE_MEM_MB)
        oversized = [size for size in demand if size > node_mem]
        if oversized:
            LOGGER.warning('%d queued allocations need more than %dMB, no worker can run them', len(oversized), node_mem)
            demand = [size for size in demand if size <= node_mem]
        required = sum(demand) + args.headroom_mb

        def by_class(klass):
            return [w for w in workers if w.klass == klass]

        def free_mb():
            return sum(w.free_mb for w in by_class(ACTIVE)) + len(by_class(BOOTING)) * node_mem

        free = free_mb()
        LOGGER.info(
            'active=%d draining=%d idle=%d booting=%d stopped=%d manual=%d unreachable=%d queued=%dMB free=%dGB',
            len(by_class(ACTIVE)), len(by_class(DRAINING)), len(by_class(IDLE)), len(by_class(BOOTING)),
            len(by_class(STOPPED)) + len(by_class(STOPPING)), len(by_class(MANUAL)), len(by_class(UNREACHABLE)),
            queued, free // 1024)

        for worker in by_class(UNREACHABLE):
            LOGGER.warning('%s is running, but its Nomad node is not ready, leaving it alone', worker.name)

        if self.paused():
            LOGGER.info('paused, doing nothing')
            return

        # workers stuck in booting
        for worker in by_class(BOOTING):
            if worker.age() > args.boot_timeout:
                LOGGER.error('%s is booting for %d min, stopping it', worker.name, worker.age() // 60)
                self.stop_instance(worker)
                worker.klass = STOPPING

        scaled_up = self.scale_up(node_mem, demand, by_class)
        if scaled_up:
            state['last_scale_up'] = now

        free = free_mb()
        surplus = free - required >= node_mem
        if not surplus:
            state.pop('surplus_since', None)
        else:
            state.setdefault('surplus_since', now)

        window_ok = (
            surplus
            and now - state['surplus_since'] >= args.scale_down_delay
            and now - state.get('last_scale_up', 0) >= args.scale_down_delay)
        if window_ok:
            self.scale_down(by_class(ACTIVE), demand, [node_mem] * len(by_class(BOOTING)))

        self.stop_idle([w for w in workers if w.klass == IDLE])
        # saved last for `surplus_since` and `last_scale_up`, `disabled` is saved by `set_eligibility()`
        self.save_state(state)

    def scale_up(self, node_mem, demand, by_class):
        args = self.args
        acted = False

        def short():
            """Workers still missing, at least enough for `min_active`."""
            capacities = [w.free_mb for w in by_class(ACTIVE)] + [node_mem] * len(by_class(BOOTING))
            opened, left = pack(demand, capacities, node_mem)
            spare = sum(capacities) + opened * node_mem - (sum(demand) - sum(left))
            headroom = max(0, math.ceil((args.headroom_mb - spare) / node_mem))
            floor = args.min_active - len(by_class(ACTIVE)) - len(by_class(BOOTING))
            return max(opened + headroom, floor)

        if short() <= 0:
            return False

        # a) draining workers, the ones with the most free memory first
        for worker in sorted(by_class(DRAINING), key=lambda w: w.free_mb, reverse=True):
            if short() <= 0:
                return acted
            self.set_eligibility(worker, True)
            worker.klass = ACTIVE
            acted = True

        # b) idle workers
        for worker in by_class(IDLE):
            if short() <= 0:
                return acted
            self.set_eligibility(worker, True)
            worker.klass = ACTIVE
            acted = True

        # c) stopped workers
        wanted = min(short(), args.max_start)
        for worker in by_class(STOPPED):
            if wanted <= 0:
                break
            if self.start_instance(worker):
                worker.klass = BOOTING
                worker.launch_time = datetime.now(timezone.utc)
                wanted -= 1
                acted = True
        if wanted > 0:
            LOGGER.warning('short of %d workers, no stopped worker left to start', wanted)
        return acted

    def scale_down(self, active, demand, booting):
        """Drain workers the queue does not need, `booting` holds the memory of the booting workers."""
        args = self.args
        drained = 0
        kept = list(active)
        for worker in sorted(active, key=lambda w: (len(w.allocs), w.used_mb)):
            if drained >= args.max_drain or len(kept) - 1 < args.min_active:
                break
            if not self.fits(demand, [w.free_mb for w in kept if w is not worker] + booting):
                continue
            self.set_eligibility(worker, False)
            worker.klass = DRAINING if worker.allocs else IDLE
            kept.remove(worker)
            drained += 1

    def stop_idle(self, idle):
        for worker in idle:
            # allocations can land between the inventory and the call
            if self.active_allocs(worker.node['ID']):
                LOGGER.info('%s got allocations, not stopping', worker.name)
                continue
            self.stop_instance(worker)
            worker.klass = STOPPING

    @staticmethod
    def _log_action(message):
        LOGGER.info('action: %s', message)

    # commands

    def resolve(self, names, workers):
        by_key = {}
        for worker in workers:
            by_key[worker.name] = worker
            by_key[worker.instance_id] = worker
        missing = [n for n in names if n not in by_key]
        if missing:
            sys.exit(f'unknown managed workers: {", ".join(missing)}')
        return [by_key[n] for n in names]

    def wait_ready(self, targets, timeout):
        deadline = time.time() + timeout
        pending = {w.instance_id: w for w in targets}
        while pending and time.time() < deadline:
            with self.locked():
                for worker in self.inventory():
                    if worker.instance_id in pending and worker.node:
                        LOGGER.info('%s is ready', worker.name)
                        if not worker.eligible:
                            self.set_eligibility(worker, True)
                            self.update_state([worker])
                        del pending[worker.instance_id]
            if pending:
                time.sleep(10)
        if pending:
            sys.exit(f'timeout waiting for: {", ".join(w.name for w in pending.values())}')

    def cmd_status(self):
        state = self.load_state()
        workers = self.inventory(set(state.get('disabled', [])), held=set(state.get('held', [])))
        queued = self.queued_mb()
        rows = [('NAME', 'INSTANCE', 'EC2', 'NOMAD', 'ELIGIBLE', 'ALLOCS', 'USED_MB', 'CLASS')]
        for w in sorted(workers, key=lambda w: w.name):
            rows.append((
                w.name, w.instance_id, w.ec2_state, w.node['Status'] if w.node else '-',
                ('yes' if w.eligible else 'no') if w.node else '-',
                str(len(w.allocs)) if w.node else '-', str(w.used_mb) if w.node else '-', w.klass))
        widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
        for row in rows:
            print('  '.join(cell.ljust(width) for cell, width in zip(row, widths)))
        counts = {}
        for w in workers:
            counts[w.klass] = counts.get(w.klass, 0) + 1
        print()
        print('total={} {} queued={}MB paused={}'.format(
            len(workers), ' '.join(f'{k}={v}' for k, v in sorted(counts.items())), queued, self.paused()))

    def cmd_start_all(self, wait):
        with self.locked():
            state = self.load_state()
            workers = self.inventory(set(state.get('disabled', [])), held=set(state.get('held', [])))
            started = []
            enabled = []
            for worker in workers:
                if worker.klass == STOPPED and self.start_instance(worker):
                    started.append(worker)
                elif worker.klass in (DRAINING, IDLE):
                    self.set_eligibility(worker, True)
                    enabled.append(worker)
            self.update_state(enabled)
        stopping = [w for w in workers if w.klass == STOPPING]
        if stopping:
            LOGGER.warning('still stopping, run again later: %s', ', '.join(w.name for w in stopping))
        manual = [w for w in workers if w.klass == MANUAL]
        if manual:
            LOGGER.warning('made ineligible by a person, left alone: %s', ', '.join(w.name for w in manual))
        if wait:
            self.wait_ready(started + [w for w in workers if w.klass == BOOTING], self.args.wait_timeout)

    def cmd_start(self, names):
        with self.locked():
            targets = self.resolve(names, self.inventory())
            for worker in targets:
                if worker.klass == STOPPED:
                    self.start_instance(worker)
                elif worker.node and not worker.eligible:
                    self.set_eligibility(worker, True)
            self.update_state(targets, hold=False)
        self.wait_ready([w for w in targets if w.klass in (STOPPED, BOOTING)], self.args.wait_timeout)

    def cmd_stop(self, names, force):
        with self.locked():
            targets = self.resolve(names, self.inventory())
            for worker in targets:
                if worker.node and worker.eligible:
                    self.set_eligibility(worker, False)
            # held, the loop does not start them while waiting for the allocations or after the stop
            self.update_state(targets, hold=True)
        for worker in targets:
            if not force:
                while worker.node and self.active_allocs(worker.node['ID']):
                    LOGGER.info('waiting for allocations of %s', worker.name)
                    time.sleep(30)
            self.stop_instance(worker)

    def cmd_eligibility(self, names, eligible):
        with self.locked():
            targets = self.resolve(names, self.inventory())
            for worker in targets:
                if not worker.node:
                    LOGGER.warning('%s has no ready node', worker.name)
                    continue
                self.set_eligibility(worker, eligible)
            # `enable` lifts the hold of `stop`, `disable` leaves the holds alone
            self.update_state(targets, hold=False if eligible else None)

    def cmd_adopt(self, names, everything):
        workers = [Worker(i) for i in self.describe(managed=False)]
        workers = [w for w in workers if not any(
            t['Key'] == TAG_KEY and t['Value'] == TAG_VALUE for t in w.instance.get('Tags', []))]
        if not everything:
            workers = self.resolve(names, workers)
        for worker in workers:
            LOGGER.info('adopt %s (%s)', worker.name, worker.instance_id)
            if not self.dry_run:
                self.ec2.create_tags(Resources=[worker.instance_id], Tags=[{'Key': TAG_KEY, 'Value': TAG_VALUE}])
        LOGGER.info('adopted %d workers', len(workers))


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--profile', default=os.environ.get('AWS_PROFILE'), help='AWS profile')
    parser.add_argument('--region', default='us-east-1')
    parser.add_argument('--nomad-host', default='127.0.0.1')
    parser.add_argument('--nomad-port', type=int, default=4646)
    parser.add_argument('--state-dir', default='/var/lib/tf-worker-scaler')
    parser.add_argument('--headroom-mb', type=int, default=0, help='memory kept free on top of the queue')
    parser.add_argument('--min-active', type=int, default=5, help='workers never drained below this count')
    parser.add_argument('--max-start', type=int, default=10, help='workers started per tick')
    parser.add_argument('--max-drain', type=int, default=5, help='workers made ineligible per tick')
    parser.add_argument('--scale-down-delay', type=int, default=600, help='seconds the surplus must hold')
    parser.add_argument('--boot-timeout', type=int, default=600, help='seconds before a booting worker is stopped')
    parser.add_argument('--wait-timeout', type=int, default=900, help='seconds to wait for started workers')

    sub = parser.add_subparsers(dest='command', required=True)

    def add(name, help_, dry_run=False):
        p = sub.add_parser(name, help=help_)
        if dry_run:
            p.add_argument('--dry-run', action='store_true', help='log the actions, do nothing')
        return p

    add('run', 'run the scaling loop', dry_run=True).add_argument('--interval', type=int, default=60)
    add('once', 'run a single tick', dry_run=True)
    add('status', 'show the workers')
    add('pause', 'pause the loop, it only logs')
    add('resume', 'resume the loop')
    add('start-all', 'start every stopped worker, for releases').add_argument('--wait', action='store_true')
    add('start', 'start workers and wait for them').add_argument('names', nargs='+')
    stop = add('stop', 'make workers ineligible, wait for 0 allocations, stop them')
    stop.add_argument('names', nargs='+')
    stop.add_argument('--force', action='store_true', help='do not wait for the allocations')
    add('enable', 'mark workers eligible').add_argument('names', nargs='+')
    add('disable', 'mark workers ineligible').add_argument('names', nargs='+')
    adopt = add('adopt', 'tag workers as managed', dry_run=True)
    adopt.add_argument('--all', action='store_true', dest='everything')
    adopt.add_argument('names', nargs='*')
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format='%(message)s', stream=sys.stdout)
    # the journal timestamps the lines, keep boto quiet
    logging.getLogger('botocore').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)

    if args.command == 'adopt' and not args.everything and not args.names:
        sys.exit('adopt needs --all or worker names')

    scaler = Scaler(args)
    cmd = args.command

    if cmd == 'run':
        while True:
            try:
                with scaler.locked():
                    scaler.tick()
            except Exception:  # noqa: BLE001 - keep the loop alive, the next tick retries
                LOGGER.exception('tick failed')
            time.sleep(args.interval)
    elif cmd == 'once':
        with scaler.locked():
            scaler.tick()
    elif cmd == 'status':
        scaler.cmd_status()
    elif cmd == 'pause':
        scaler.set_paused(True)
    elif cmd == 'resume':
        scaler.set_paused(False)
    elif cmd == 'start-all':
        scaler.cmd_start_all(args.wait)
    elif cmd == 'start':
        scaler.cmd_start(args.names)
    elif cmd == 'stop':
        scaler.cmd_stop(args.names, args.force)
    elif cmd == 'enable':
        scaler.cmd_eligibility(args.names, True)
    elif cmd == 'disable':
        scaler.cmd_eligibility(args.names, False)
    elif cmd == 'adopt':
        scaler.cmd_adopt(args.names, args.everything)


if __name__ == '__main__':
    main()
