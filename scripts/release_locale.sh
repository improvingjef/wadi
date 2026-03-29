#!/bin/sh

oasis_release_archive_locale() {
  if command -v locale >/dev/null 2>&1; then
    available_locales=$(locale -a 2>/dev/null || true)
    for candidate in C.UTF-8 C.utf8; do
      if printf '%s\n' "$available_locales" | grep -F -x -- "$candidate" >/dev/null 2>&1; then
        printf '%s\n' "$candidate"
        return
      fi
    done
  fi

  printf 'C\n'
}

oasis_apply_release_archive_env() {
  archive_locale=$(oasis_release_archive_locale)
  export LANG=$archive_locale
  export LC_ALL=$archive_locale
  export TZ=UTC
  export COPYFILE_DISABLE=1
}
