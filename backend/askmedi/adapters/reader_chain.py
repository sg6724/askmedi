from collections.abc import Sequence

from askmedi.domain.search import DocumentReader, VisionUnavailable


class DocumentReaderChain:
    """Tries each reader in order. Only VisionUnavailable moves on; an unreadable document
    (the model answered with nothing usable) is final."""

    def __init__(self, readers: Sequence[DocumentReader]) -> None:
        self._readers = list(readers)

    async def read_json(self, prompt: str, data: bytes, mime_type: str) -> dict:
        errors: list[str] = []
        for reader in self._readers:
            try:
                return await reader.read_json(prompt, data, mime_type)
            except VisionUnavailable as exc:
                errors.append(str(exc))
        raise VisionUnavailable("; ".join(errors))
