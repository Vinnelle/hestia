proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header Connection "";
proxy_connect_timeout 2s;
proxy_read_timeout 5s;
proxy_hide_header Set-Cookie;
proxy_ignore_headers Set-Cookie;

add_header X-Frame-Options           "SAMEORIGIN"                            always;
add_header X-Content-Type-Options    "nosniff"                               always;
add_header Referrer-Policy           "strict-origin-when-cross-origin"       always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains"   always;
add_header Content-Security-Policy   "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; object-src 'none'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'" always;
