#!/bin/sh
omarchy-shell shell putBarWidget io.github.quacknode.g14 '{"section":"right","before":"quack.power"}' >/dev/null 2>&1 || true
exec omarchy-shell shell summon io.github.quacknode.g14
