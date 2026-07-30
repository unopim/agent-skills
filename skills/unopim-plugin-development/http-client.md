# cURL HTTP Client

UnoPim connectors use native cURL — never Guzzle, never the Laravel `Http` facade.
In-repo exemplar: `packages/Webkul/AiAgent/src/Http/Client/AiApiClient.php` with
`packages/Webkul/AiAgent/src/Http/Client/BearerToken.php`.

## Rules

- Check `curl_errno()` after every `curl_exec()`; always `curl_close()`.
- HTTP >= 400 throws the module's `ApiException` with the status code.
- Any user-supplied base URL is an SSRF surface: validate it with
  `Webkul\Webhook\Validators\SafeWebhookUrl` and pin the connection via its
  `httpOptions()` `CURLOPT_RESOLVE` entry with `CURLOPT_FOLLOWLOCATION => false`, as
  `AiApiClient::execute()` does. Never fetch a raw admin-typed URL.
- Never log the API key or the decrypted credential — log status codes and endpoints.
- Bind the client and any credential-holding service `scoped()`, NEVER `singleton()` —
  the client's `configure()` mutates per-credential state and this stack runs Octane
  (see `packages/Webkul/AiAgent/src/Providers/AiAgentServiceProvider.php`
  `registerBindings()`).
- Constructor-injecting the client into a controller for a one-shot flow is house style
  (`packages/Webkul/AiAgent/src/Http/Controllers/CredentialController.php` does it for
  `testConnection`). Wrap multi-call orchestration in a scoped `Services/` class so
  controllers stay thin.

## Auth strategies

Separate classes that apply options to the cURL handle. Exemplar: `BearerToken.php`.

```php
<?php

namespace Webkul\{ModuleName}\Http\Client;

class BearerToken
{
    public function __construct(
        protected string $token,
    ) {}

    /**
     * Apply Bearer token authentication to a cURL handle.
     *
     * @param  resource|\CurlHandle  $ch
     */
    public function apply($ch): void
    {
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer '.$this->token,
            'Content-Type: application/json',
            'Accept: application/json',
        ]);
    }
}
```

For key/secret APIs, a `BasicAuth` strategy follows the same shape:

```php
<?php

namespace Webkul\{ModuleName}\Http\Client;

class BasicAuth
{
    public function __construct(
        protected string $key,
        protected string $secret,
    ) {}

    /**
     * Apply HTTP Basic credentials to a cURL handle.
     *
     * @param  resource|\CurlHandle  $ch
     */
    public function apply($ch): void
    {
        curl_setopt($ch, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
        curl_setopt($ch, CURLOPT_USERPWD, $this->key.':'.$this->secret);
    }
}
```

## ApiClient template

```php
<?php

namespace Webkul\{ModuleName}\Http\Client;

use Webkul\{ModuleName}\Exceptions\ApiException;
use Webkul\Webhook\Validators\SafeWebhookUrl;

class ApiClient
{
    protected string $baseUrl = '';

    protected string $apiKey = '';

    /**
     * Configure the client for one credential.
     */
    public function configure(string $baseUrl, string $apiKey): static
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->apiKey = $apiKey;

        return $this;
    }

    /**
     * Build a full API URL from an endpoint path.
     */
    public function buildApiUrl(string $endpoint): string
    {
        return $this->baseUrl.'/'.ltrim($endpoint, '/');
    }

    /**
     * Issue a GET request.
     *
     * @param  array<string, mixed>  $params
     * @return array<mixed>
     */
    public function get(string $endpoint, array $params = []): array
    {
        $url = $this->buildApiUrl($endpoint);

        if ($params !== []) {
            $url .= '?'.http_build_query($params);
        }

        return $this->execute('GET', $url);
    }

    /**
     * Issue a POST request.
     *
     * @param  array<mixed>  $data
     * @return array<mixed>
     */
    public function post(string $endpoint, array $data = []): array
    {
        return $this->execute('POST', $this->buildApiUrl($endpoint), $data);
    }

    /**
     * Execute a cURL request with SSRF pinning.
     *
     * @param  array<mixed>|null  $data
     * @return array<mixed>
     *
     * @throws ApiException
     */
    protected function execute(string $method, string $url, ?array $data = null): array
    {
        $safeOptions = SafeWebhookUrl::httpOptions($url);

        throw_unless(
            isset($safeOptions['curl'][CURLOPT_RESOLVE]),
            ApiException::class,
            trans('{module}::app.client.unsafe-api-url'),
            422
        );

        $ch = curl_init();

        $options = [
            CURLOPT_URL            => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 30,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_RESOLVE        => $safeOptions['curl'][CURLOPT_RESOLVE],
            CURLOPT_HTTPHEADER     => [
                'Authorization: Bearer '.$this->apiKey,
                'Content-Type: application/json',
                'Accept: application/json',
            ],
        ];

        if ($method === 'POST' && $data !== null) {
            $options[CURLOPT_POST] = true;
            $options[CURLOPT_POSTFIELDS] = json_encode($data);
        }

        if (in_array($method, ['PUT', 'DELETE'], true)) {
            $options[CURLOPT_CUSTOMREQUEST] = $method;
        }

        curl_setopt_array($ch, $options);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        $curlErrno = curl_errno($ch);

        curl_close($ch);

        throw_if($curlErrno !== 0, ApiException::class, 'cURL error: '.$curlError, $curlErrno);

        $decoded = json_decode((string) $response, true);

        if ($httpCode >= 400) {
            $message = $decoded['message'] ?? trans('{module}::app.client.unknown-api-error');

            throw new ApiException('API error ('.$httpCode.'): '.$message, $httpCode);
        }

        return $decoded ?? [];
    }
}
```

## ApiException

Exemplar: `packages/Webkul/AiAgent/src/Exceptions/ApiException.php`.

```php
<?php

namespace Webkul\{ModuleName}\Exceptions;

use RuntimeException;

class ApiException extends RuntimeException
{
}
```

## Container binding

```php
$this->app->scoped(ApiClient::class);
$this->app->scoped({ModuleName}Service::class);
```

`singleton()` here leaks one admin's credentials into the next Octane request — the
codebase reserves `singleton()` for stateless registries (see the scoped/singleton split
in `AiAgentServiceProvider::registerBindings()`).

## Checklist

- [ ] Native cURL; `curl_errno()` checked; handle closed.
- [ ] `SafeWebhookUrl::httpOptions()` pin + `CURLOPT_FOLLOWLOCATION => false`.
- [ ] 4xx/5xx throws `ApiException` with the HTTP code; no secrets in messages or logs.
- [ ] Auth strategies are separate classes applying options to the handle.
- [ ] Client and service bound `scoped()`; overridable `buildApiUrl()` for
      version-prefixed APIs.
