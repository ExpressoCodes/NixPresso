{ pkgs, ... }:

# Periodically checks the dotfiles git repo for upstream commits.
# If new commits exist, fires a mako notification via notify-send using
# the "NixStore" app name so it appears alongside package update notices.
# Reads /etc/nixos/.dotfiles-vars (written by install.sh) for the repo path.
{
  systemd.user.services.dotfiles-update-check = {
    description = "Check dotfiles repo for upstream updates";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dotfiles-update-check" ''
        set -euo pipefail

        VARS=/etc/nixos/.dotfiles-vars
        [ -f "$VARS" ] || exit 0
        # shellcheck source=/dev/null
        source "$VARS"

        REPO="$DOTFILES_REPO"
        [ -d "$REPO/.git" ] || exit 0

        # Fetch quietly; bail out if there's no network
        ${pkgs.git}/bin/git -C "$REPO" fetch --quiet origin 2>/dev/null || exit 0

        LOCAL=$(${pkgs.git}/bin/git -C "$REPO" rev-parse HEAD)
        REMOTE=$(
          ${pkgs.git}/bin/git -C "$REPO" rev-parse origin/HEAD 2>/dev/null ||
          ${pkgs.git}/bin/git -C "$REPO" rev-parse origin/main  2>/dev/null ||
          ${pkgs.git}/bin/git -C "$REPO" rev-parse origin/master 2>/dev/null
        ) || exit 0

        [ "$LOCAL" != "$REMOTE" ] || exit 0   # already up to date

        COUNT=$(${pkgs.git}/bin/git -C "$REPO" rev-list --count HEAD.."$REMOTE" 2>/dev/null || echo "?")
        TITLES=$(${pkgs.git}/bin/git -C "$REPO" log --oneline HEAD.."$REMOTE" 2>/dev/null \
          | head -4 | sed 's/^[a-f0-9]* /• /' | paste -sd $'\n')

        ${pkgs.libnotify}/bin/notify-send \
          --app-name "NixStore" \
          --urgency normal \
          --icon system-software-update \
          "Dotfiles update available ($COUNT commit(s))" \
          "$TITLES"$'\n'"Run: cd $REPO && ./update.sh"
      '';
    };
  };

  systemd.user.timers.dotfiles-update-check = {
    description = "Check dotfiles for upstream updates every 6 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";       # first check shortly after login
      OnUnitActiveSec = "6h";
      Persistent = true;        # catch up if the machine was off
    };
  };
}
