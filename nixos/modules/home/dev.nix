# Development tooling: declarative dev shells via direnv + nix-direnv.
{ ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
