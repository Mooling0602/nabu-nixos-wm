# User-level CJK and mono fonts (system-level desktop fonts live in
# ../system/desktop.nix; fontconfig is enabled there via fonts.packages).
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    sarasa-gothic
    noto-fonts-cjk-serif
    maple-mono.NF-CN
  ];
}
