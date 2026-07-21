HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000

autoload -Uz compinit
compinit

# kubectl uses ~/.kube/config (admin kubeconfig copied in by the entrypoint)
alias k=kubectl

# VS Code Remote Tunnel. --cli-data-dir points at the momus-vscode-state PVC
# so the GitHub/Microsoft device-auth registration survives pod restarts.
# First run: use vstunnel (foreground) to complete the interactive device-code
# login. After that, vstunnel-bg relaunches it detached in tmux so it keeps
# running after you disconnect; reattach with `tmux attach -t vstunnel`.
alias vstunnel='code tunnel --accept-server-license-terms --name momus --cli-data-dir /home/ida/.vscode-cli'
alias vstunnel-bg='tmux new-session -d -s vstunnel "code tunnel --accept-server-license-terms --name momus --cli-data-dir /home/ida/.vscode-cli"'

eval "$(starship init zsh)"
