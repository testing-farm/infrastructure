Role Name
=========

Mount volume to a defined path, configure user and group of the mount point

Requirements
------------

Set `tft_worker_volume_attach` variable to `true` to activate executing of the role

Role Variables
--------------

* `tft_worker_volume_attached_device` - Device to attach
* `tft_worker_volume_attached_device_mount_path` - Path to mount point
* `tft_worker_volume_attached_device_owner` - Owner of the mount point
* `tft_worker_volume_attached_device_group` - Group of the mount point

License
-------

BSD
