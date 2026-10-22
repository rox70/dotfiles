# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
.PHONY: bootstrap overlay status pull add-repo workspace update addons addons-sync plugin marketplace
bootstrap: ; ./scripts/bootstrap.sh       # clone missing repos + workspace + overlay
overlay:   ; ./scripts/overlay.sh link    # adopt new AI files and relink everywhere
status:    ; ./scripts/overlay.sh status  # git status of repos and worktrees: must be clean
pull:      ; ./scripts/pull-all.sh
workspace: ; ./scripts/gen-workspace.sh   # regenerate the .code-workspace from repos.conf
add-repo:  ; ./scripts/add-repo.sh $(ALIAS) $(URL) $(BRANCH)  # make add-repo ALIAS=api URL=git@... [BRANCH=<branch>]
update:    ; orch-update                  # refresh managed scripts from dotfiles/orchestrator
# Optional AI tooling, nothing preinstalled: openspec-cli openspec speckit mattpocock superpowers + any plugin
addons:    ; ./scripts/addon.sh list      # what is available, selected (addons.conf) and installed
addon-%:   ; ./scripts/addon.sh install $* $(REPOS)  # make addon-openspec | addon-all [REPOS="fe be"] (default: all repos)
plugin:    ; ./scripts/addon.sh plugin $(P) $(REPOS)  # make plugin P="<name>@<marketplace> ..." [REPOS="fe be"]
marketplace: ; ./scripts/addon.sh marketplace $(NAME) $(URL)  # make marketplace NAME=<name> URL=<git URL|owner/repo>
addons-sync: ; ./scripts/addon.sh sync    # reinstall the addons.conf selection at the latest versions
