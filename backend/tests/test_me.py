def test_me_requires_token(client):
    assert client.get("/me").status_code == 401


def test_me_rejects_bad_token(client):
    response = client.get("/me", headers={"Authorization": "Bearer nope"})
    assert response.status_code == 401


def test_me_returns_user(client):
    response = client.get("/me", headers={"Authorization": "Bearer good-token"})
    assert response.status_code == 200
    assert response.json() == {"user_id": "user-1", "email": "u1@test.dev"}
