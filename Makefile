%.pdf: %.md
	pandoc -o $@ $^

.PHONY: pdf all
pdf: onionPathsProposal.pdf
all: pdf
