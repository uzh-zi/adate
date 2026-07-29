import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def fake_backend(monkeypatch):
    monkeypatch.setenv("APPKIT_BACKEND", "fake")
    import appkit

    appkit.reset_fakes()
    yield
    appkit.reset_fakes()


@pytest.fixture
def client():
    from app.main import app

    return TestClient(app)
