from dataclasses import dataclass

from askmedi.domain.audit import AuditLogger
from askmedi.domain.auth import TokenVerifier
from askmedi.domain.llm import LLMProvider


@dataclass
class Container:
    token_verifier: TokenVerifier
    llm: LLMProvider
    audit: AuditLogger
