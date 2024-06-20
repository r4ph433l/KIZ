#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='\[\e[31m\]\u@\h\[\e[37m\]:\[\e[34m\]\W\[\e[37m\]\$ '

neofetch
