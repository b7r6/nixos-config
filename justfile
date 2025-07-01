# https://just.systems/

default:
    @just --list

[group('main')]
run:
    nix run

[group('main')]
update:
    nix flake update

[group('dev')]
lint:
    nix fmt

[group('dev')]
check:
    nix flake check

[group('dev')]
dev:
    nix develop
