
## Make certs:
```
docker pull newzyer/mkcert
mkcert() { docker run -it --rm -v $PWD:/certs newzyer/mkcert mkcert "$@"; }
X509() { docker run -i --rm -v $PWD:/certs newzyer/mkcert X509 "$@"; }

mkcert --make-root --cacert ca.crt --cakey ca.key "CN=Magic Box Root CA"
mkcert --ica --nochain --cacert ca.crt --cakey ca.key -o ica "/CN=mgbox ICA/O=nulabs/C=cn" --validity 3650
mkcert --cacert ica.crt --cakey ica.key -o mgbox --dns "mgbox" --dns "mgbox.nulabs.cn" "/CN=mgbox/O=nullabs/C=cn" --validity 3650

X509 ca.crt
X509 mgbox.crt
```
