# VPS fabryki: checklista

OVH VPS-1 (BHS), Debian 13. Większość robi [`bootstrap.sh`](../bootstrap.sh). Tu są kroki, których skrypt nie zrobi, w kolejności.

**Cel:** publicznie otwarte nic poza UDP 41641 (Tailscale). Dostęp: laptop/telefon → Tailscale → SSH → Herdr/tmux.
**Użytkownicy:** `debian` (admin, sudo) i `factory` (agenci, bez sudo).

> **Ratunek:** konsola KVM w panelu OVH (VPS → „KVM”) albo rescue mode. Zapamiętaj, gdzie są, zanim zaczniesz.

## 1. Przed bootstrapem

- [ ] Panel OVH: dodaj klucz publiczny w *Konto → Klucze SSH* (przyda się przy rebuildzie).
- [ ] Z laptopa: `ssh-copy-id debian@<IP>` i sprawdź, że `ssh debian@<IP>` wchodzi kluczem bez hasła.
      Bez tego skrypt przerwie pracę, bo wyłączenie haseł odcięłoby dostęp.
- [ ] Tailscale admin console → *Access controls*: scal [`tailscale/policy.hujson`](../tailscale/policy.hujson) z obecną polityką.
  - `tagOwners` dla `tag:factory` musi być **przed** bootstrapem, inaczej `tailscale up --advertise-tags` się nie uda.
  - Usuń domyślny grant „allow all”. Podmień `you@example.com` w `tests` na swój login (tylko w konsoli, nie w repo).
  - Sprawdź, że RPi i inne urządzenia nadal działają jak trzeba.
- [ ] (opcjonalnie) Auth key: *Settings → Keys → Generate auth key*, jednorazowy, z tagiem `tag:factory`.
      Bez niego `tailscale up` wypisze link do zalogowania w przeglądarce.

## 2. Bootstrap

```bash
scp bootstrap.sh debian@<IP>:
ssh -t debian@<IP> 'sudo bash bootstrap.sh'
```

Z auth keyem: `ssh -t debian@<IP> 'read -rsp "TS key: " k; sudo TS_AUTHKEY="$k" bash bootstrap.sh'` (klucz nie trafia do historii shella).

- [ ] Skrypt doszedł do „Bootstrap done”, w sprawdzeniach nie ma `MISSING` (poza ewentualnie `herdr`).
- [ ] **Nie zamykaj tej sesji.** W nowym terminalu: `ssh debian@<IP>` dalej wchodzi kluczem.
- [ ] Jeśli skrypt pisze „Reboot required”: `sudo reboot`, potem uruchom go jeszcze raz (powinien przejść bez zmian).

## 3. Zamknięcie publicznego SSH

- [ ] Urządzenie `factory` w Tailscale ma tag `tag:factory` i wyłączony key expiry (tagi mają to domyślnie).
- [ ] Z laptopa przez MagicDNS: `ssh debian@factory` i `ssh factory@factory` działają.
- [ ] W sesji **przez Tailscale**: `ssh -t debian@factory 'sudo bash bootstrap.sh --lockdown'`.
      Skrypt odmówi, jeśli nie widzi sesji SSH z adresu Tailscale.
- [ ] Z laptopa: `nc -vz -w5 <IP> 22` kończy się timeoutem, a `ssh debian@factory` dalej działa.
- [ ] Z `tag:factory` nie da się dosięgnąć innych urządzeń, np. na VPS-ie `nc -vz -w5 <ip-tailscale-rpi> 22` → timeout.

## 4. Laptop

- [ ] `~/.ssh/config`:
  ```
  Host factory
      HostName factory
      User factory
  Host factory-admin
      HostName factory
      User debian
  ```
- [ ] Herdr (jeśli się zainstalował): `herdr machine add factory`, potem `herdr --remote factory`.

## 5. Sekrety (na VPS-ie jako `factory`)

Oba trafiają do `~/.config/factory/env` (chmod 600, tworzy go bootstrap). Plik jest ładowany przez `~/.config/factory/shellrc` na początku `.bashrc`.

- [ ] **Claude:** na laptopie `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN=...` w `env`.
      Token działa rok i daje tylko inferencję. Wyciek = odwołanie i nowy token.
- [ ] **GitHub:** konto `ellie-7894` → *Settings → Developer settings → Tokens (classic)*: nowy token „factory”, **tylko scope `repo`**
      (bez `workflow`, bez `delete_repo`), z datą wygaśnięcia → `GH_TOKEN=...` w `env`.
      Fine-grained PAT nie działa dla collaboratora na cudzym repo osobistym, stąd classic.
- [ ] Test: `ssh factory 'gh auth status && claude -p "powiedz cześć"'`.
- [ ] Commity idą jako `ellie-7894` (git config ustawia bootstrap); push przez `gh auth git-credential`.

## 6. Na koniec

- [ ] Snapshot w panelu OVH (trzymany jest jeden, ~1,30 zł netto/mies.).
- [ ] Test idempotentności: `ssh -t factory-admin 'sudo bash bootstrap.sh'` przechodzi drugi raz bez błędów i nie otwiera portu 22.

## Otwarte

- Jak Herdr ma wstawać po reboocie (unit `systemd --user`?). Docs nie opisują unitu; `loginctl enable-linger factory` jest już ustawione.
- Rebuild z API OVH (`POST /vps/{id}/rebuild`) + bootstrap jako jeden krok.

## Done

| Krok | Data | Uwagi |
|---|---|---|
| Przed bootstrapem | | |
| Bootstrap | | |
| Lockdown | | |
| Laptop | | |
| Sekrety | | |
| Snapshot | | |
