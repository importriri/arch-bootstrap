# Problem index

These notes preserve failures that changed the installer or its verification
contract. Each page records the observed symptom, the unsafe assumption and
the check that now prevents a regression.

- [`arch-chroot-bind-mounted-resolv-conf.md`](arch-chroot-bind-mounted-resolv-conf.md)
  explains why a bind-mounted resolver file must not be replaced as a regular
  file during installation.
- [`argon2id-is-built-into-cryptsetup.md`](argon2id-is-built-into-cryptsetup.md)
  records the portable Argon2 capability probe used by the storage path.
- [`bats-negative-assertion-that-asserted-nothing.md`](bats-negative-assertion-that-asserted-nothing.md)
  documents a negative test that once passed without observing its target.
- [`losetup-loop-module-not-loaded.md`](losetup-loop-module-not-loaded.md)
  covers disposable storage tests on systems where the loop module is not
  loaded yet.
- [`luks-passphrase-trailing-newline.md`](luks-passphrase-trailing-newline.md)
  explains the passphrase transport rule used by real LUKS2 tests.
- [`testing-without-udev-or-device-mapper.md`](testing-without-udev-or-device-mapper.md)
  defines why the complete storage gate requires an Arch-capable VM instead of
  a restricted container.
