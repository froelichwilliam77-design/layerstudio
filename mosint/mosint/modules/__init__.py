"""Built-in OSINT modules."""

from __future__ import annotations

from .base import Module, ModuleResult, Status, Target
from .breaches import BreachModule
from .domain import DomainModule
from .mailserver import MailServerModule
from .social import SocialModule
from .validation import EmailValidationModule, InvalidEmailError, parse_email

# Order defines the default run order in reports.
ALL_MODULES: list[type[Module]] = [
    EmailValidationModule,
    MailServerModule,
    BreachModule,
    SocialModule,
    DomainModule,
]

MODULES_BY_NAME: dict[str, type[Module]] = {cls.name: cls for cls in ALL_MODULES}

__all__ = [
    "Module",
    "ModuleResult",
    "Status",
    "Target",
    "BreachModule",
    "DomainModule",
    "MailServerModule",
    "SocialModule",
    "EmailValidationModule",
    "InvalidEmailError",
    "parse_email",
    "ALL_MODULES",
    "MODULES_BY_NAME",
]
