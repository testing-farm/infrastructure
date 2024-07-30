import re
import random

from typing import Any, Pattern  # noqa

EvalContextType = dict[str, Any]


def MATCH(eval_context: EvalContextType, pattern: Pattern[str], text: str):
    return re.match(pattern, text)
