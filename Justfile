set shell := ["bash", "-euo", "pipefail", "-c"]

default:
	@just --list

pdf report:
	@bash -c 'file=$(find reports -maxdepth 3 -type f -name "{{report}}_*.md" | head -n 1); \
	if [ -z "$file" ]; then echo "no report matching {{report}}_*.md" >&2; exit 1; fi; \
	out="${file%.md}.pdf"; echo "Generating $out from $file"; \
	pandoc "$file" --from markdown --pdf-engine=xelatex --output "$out"'
