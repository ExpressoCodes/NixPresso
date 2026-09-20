#!/usr/bin/env bash
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
dconf write /org/gnome/nautilus/icon-view/default-zoom-level "'small-plus'"
dconf write /org/gnome/settings-daemon/plugins/color/night-light-schedule-automatic false
