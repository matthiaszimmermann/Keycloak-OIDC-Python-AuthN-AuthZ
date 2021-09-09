# Keycloak Python OIDC AuthN/AuthZ

Setup Ingredients

* Keycloak
* Python
* Docker
* curl
* jq

## Start Keycloak Server

Start keycloak server via Docker according to [Keycloak Server repository](https://github.com/keycloak/keycloak-containers/tree/master/server)

```bash
docker run \
-d --name keycloak \
-p 8080:8080 \
-e KEYCLOAK_USER=admin \
-e KEYCLOAK_PASSWORD=password \
jboss/keycloak
```

And to follow the logs of the Keycloak container

```bash
docker logs -f keycloak
```

## Admin Login, Realm and Users

Admin Login via browser

`http://localhost:8080/auth/`

Startup may take a while for a first login after starting the container. 
Following the keycloak logs provides insight into the startup process.

Once the Keycloak page is ready in the browser login with the above defined credentials for the admin user: `admin/password`

## Authentication Setup

For the authentication (AuthN) setup we will prepare the following elements

* Realm `acme`
* User `alice`
* User `bob`
* Client `system_a`
* Client `system_b`

System `system_a` has an actual Python implementation with the following elements

* Unprotected home page http://localhost:5002/
* Login page http://localhost:5002/private
* Logout page http://localhost:5002/logout
* Protected API endpoint 1 for bearer token access http://localhost:5002/api
* Protected API endpoint 2 for bearer token access http://localhost:5002/api2

System `system_b` only has a representation inside Keycloak. 
This is enough for testing of the client credentials grant. 

### Realm

A realm represents the context for users, clients, roles, groups etc. 
Keycloak comes with a ream `master` which is reserved for its own purposes.

A straight forward/simple approach is to create a new realm for each tenant or organisation.
For our case we create a new realm `acme` that will be used to manage all users, clients etc that we need.

Create realm for application according to [Keycloak Getting Started](https://www.keycloak.org/getting-started/getting-started-docker)

Use `acme` for the name of the new realm.

### Users 

Add one or more users according to the getting started guide.

* `alice` with password `password_alice` (name: Alice, last name: Anderson, email: alice@acme.com)

* `bob` with password `password_bob` (name: Bob, last name: Brown, email: bob@acme.com)


Open the 'normal' user management web interface (note the realm name in the URL)

`http://localhost:8080/auth/realms/acme/account/#/`

### Client "system_a"

* `system_a` with client protocol `openid-connect` and access type `confidential`
* set valid reddirect uri to `http://localhost:5002/*`

In Keycloak, copy the `Secret` from tab `Credentials` into attribute `client_secret` json files

* client_secrets_acme.json
* client_secrets_acme_ip.json

```json
{
    "web": {
        "issuer": "http://localhost:8080/auth/realms/acme",
        "auth_uri": "http://localhost:8080/auth/realms/acme/protocol/openid-connect/auth",
        "client_id": "system_a",
        "client_secret": "3672375c-79fe-4803-b332-77f0bad28442",
        "redirect_uris": [
            "http://localhost:5002/*"
         ...
```

### Client "system_b" (Client Credentials Grant)

* `system_b` with client protocol `openid-connect` and access type `confidential`
* set service accounts enabled to `ON`
* set valid reddirect uri to `http://localhost:5003/*`

## Authorization Setup

The authorization setup targets access via bearer tokens to the API endpoints of client `system_a`.
The goal is to create a setup that grants access according to the table below.

| Preferred_username       | Client role       | Access /api   | Access /api2   |
| ------------------------ | ----------------- | ------------- | ------------- |
| alice                    | api_superuser     | Granted       | Granted       |
| bob                      | api_user          | Granted       | Denied        |
| service-account-system_b | api_user_system_b | Denied        | Granted       |

### Client Roles

Now add some client roles.
Select client `system_a` in the Keycloak admin UI and switch to the Roles tab, then

* add role `api_1` (needs to match with code for required role for endpoint /api)
* add role `api_2` (needs to match with code for required role for endpoint /api2)
* add role `api_superuser`, set property Composite Roles to ON and add from client roles both roles from above
* add role `api_user`, set property Composite Roles to ON and add from client roles role `api_1`
* add role `api_user_system_b`, set property Composite Roles to ON and add from client roles role `api_2`

### Assign Roles to Users Alice and Bob

Link some client roles to the users.

* Add client role `api_superuser` to user `alice` in tab "Role Mappings"
* Add client role `api_user` to user `bob` in tab "Role Mappings"

### Assign Roles to Client "system_b"

Link some client roles to the users.

* Add client role `api_user_system_b` to client `system_b` in tab "Service Account Roles"

## Prepare and Run the Target System (system_a)

The target system may be run using a classical setup or using a dockerized version.

### Classical Setup 

Install Python dependencies

```bash
pip3 install --no-cache-dir -r requirements.txt
```

In `application.py` use the following snippet.

```python
app.config.update({
    'OIDC_OPENID_REALM': 'acme',
    'OIDC_CLIENT_SECRETS': 'client_secrets_acme.json',
    ...
```

And a the end

```python
if __name__ == '__main__':
    app.run(host='localhost', port=5002)
```

Then, start the application

```bash
python3 application.py
```

Check the application in the browser using [http://localhost:5002/](http://localhost:5002/)

### Dockerized Setup

For `client_secrets_acme_ip.json` ensure that the IP address of the keycloak matches localhost (localhost inside the container is not what we want, we want to call the Keycloak outside the container).

To obtain this IP address you may use the information provided via command line.

```bash
ifconfig | grep 'inet '
```

In `application.py` use the following snippet.

```python
app.config.update({
    'OIDC_OPENID_REALM': 'acme',
    'OIDC_CLIENT_SECRETS': 'client_secrets_acme_ip.json',
    ...
```

And a the end

```python
if __name__ == '__main__':
    app.run(host='0.0.0.0')
```

Run docker container in interactive mode

```bash
docker run -p 5002:5000 -v $PWD:/app -it --rm oidc_test bash
```

Inside the container start the application

```bash
python3 application.py
```

## API Call with Bearer Token for Alice and Bob

Insprired by one of the few more complete [flask keycloak tutorials](https://github.com/DustinKLo/flask_keycloak_test).

Create bearer token for user `alice` using curl

```bash
USERNAME=alice
PASSWORD=password_alice
CLIENT_SECRET=3672375c-79fe-4803-b332-77f0bad28442
AUTH_TOKEN=`curl -s \
  -d "client_id=system_a" -d "client_secret=$CLIENT_SECRET" \
  -d "username=$USERNAME" -d "password=$PASSWORD" \
  -d "grant_type=password" \
  "http://localhost:8080/auth/realms/acme/protocol/openid-connect/token" | jq -r '.access_token'`
```

Now access API endpoint using the bearer token

```bash
curl -s -H "Authorization: Bearer $AUTH_TOKEN" http://localhost:5002/api | jq | cat
curl -s -H "Authorization: Bearer $AUTH_TOKEN" http://localhost:5002/api2 | jq | cat
```

The expected result of the above commands is shown below

```bash
{
  "message": "hello from endpoint /api1: welcome alice (8fcf95a3-661b-4f39-8cd7-258b837781ad)"
}
...
{
  "message": "hello from endpoint /api2: welcome alice (8fcf95a3-661b-4f39-8cd7-258b837781ad)"
}```


Also create a bearer token for user `bob`

```bash
USERNAME_BOB=bob
PASSWORD_BOB=password_bob
CLIENT_SECRET=3672375c-79fe-4803-b332-77f0bad28442
AUTH_TOKEN_BOB=`curl -s \
  -d "client_id=system_a" -d "client_secret=$CLIENT_SECRET" \
  -d "username=$USERNAME_BOB" -d "password=$PASSWORD_BOB" \
  -d "grant_type=password" \
  "http://localhost:8080/auth/realms/acme/protocol/openid-connect/token" | jq -r '.access_token'`
```

Now access API endpoint using the bearer token

```bash
curl -s -H "Authorization: Bearer $AUTH_TOKEN_BOB" http://localhost:5002/api | jq | cat
curl -s -H "Authorization: Bearer $AUTH_TOKEN_BOB" http://localhost:5002/api2 | jq | cat
```

The expected result of the above commands is shown below

```bash
{
  "message": "hello from endpoint /api1: welcome bob (d5ef5674-0e05-4da5-a0fa-d982b2040e87)"
}
...
{
  "error": "access denied, required role missing"
}
```

When working with non-sensitive test tokens, the content of `access_token` may be explored online using [jwt.io](https://jwt.io/) or similar services.

To inspect the full json format token online serives as [jsoneditoronline.org](https://jsoneditoronline.org) may be helpful.

## API Call from Client "system_b"

Somehwat inspired by the [client credential grant tutorial](https://www.appsdeveloperblog.com/keycloak-client-credentials-grant-example/)

Create bearer access token for system_b using client credential grant type.

```bash
CLIENT_SECRET_B=cca5080d-66db-4033-a7ec-99c0ff9ec43c
AUTH_TOKEN_B=`curl -s \
  -d "client_id=system_b" -d "client_secret=$CLIENT_SECRET_B" \
  -d "grant_type=client_credentials" \
  "http://localhost:8080/auth/realms/acme/protocol/openid-connect/token" | jq -r '.access_token'`
```

Token can then be used in exact same way to access system_a api services.

```bash
curl -s -H "Authorization: Bearer $AUTH_TOKEN_B" http://localhost:5002/api | jq | cat
curl -s -H "Authorization: Bearer $AUTH_TOKEN_B" http://localhost:5002/api2 | jq | cat
```

The expected result of the above commands is shown below

```bash
{
  "error": "access denied, required role missing"
}
...
{
  "message": "hello from endpoint /api2: welcome service-account-system_b (3401daae-461e-49e0-abde-9aed97108da7)"
}
```
