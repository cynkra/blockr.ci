#!/usr/bin/env Rscript
# Validate the deps block and emit `extra-packages` / `ref` to GITHUB_OUTPUT.
#
# Env vars (all set by parse-deps.sh):
#   DEPS_LINES    : newline-separated deps-block entries (already stripped of
#                   fences, comments, blanks)
#   DESC_PATH     : path to DESCRIPTION (may be "" if none was found)
#   PKG           : owner/repo this run is asking for a `ref` for ("" if none)
#   BASE_PACKAGES : the extra-packages output, verbatim (deps-block entries
#                   are NEVER appended)
#   GITHUB_OUTPUT : path to write outputs to

suppressPackageStartupMessages(library(pkgdepends))

env <- function(x) Sys.getenv(x, unset = "")

deps_text <- env("DEPS_LINES")
desc_path <- env("DESC_PATH")
pkg_filter <- env("PKG")
base_pkgs <- env("BASE_PACKAGES")
out_path <- env("GITHUB_OUTPUT")

refs <- if (nzchar(deps_text)) {
  x <- strsplit(deps_text, "\n", fixed = TRUE)[[1]]
  x <- trimws(x)
  x[nzchar(x)]
} else {
  character()
}

parsed <- if (length(refs)) parse_pkg_refs(refs) else list()

forward_deps <- character()
if (nzchar(desc_path) && file.exists(desc_path)) {
  d <- read.dcf(desc_path)
  for (f in intersect(c("Imports", "Depends", "LinkingTo", "Suggests"),
                      colnames(d))) {
    x <- strsplit(d[1, f], ",")[[1]]
    x <- trimws(x)
    x <- sub("\\s*\\(.*$", "", x)
    forward_deps <- c(forward_deps, x)
  }
  if ("Remotes" %in% colnames(d)) {
    remote_lines <- trimws(strsplit(d[1, "Remotes"], ",")[[1]])
    remote_lines <- remote_lines[nzchar(remote_lines)]
    if (length(remote_lines)) {
      remote_parsed <- tryCatch(parse_pkg_refs(remote_lines),
                                error = function(e) NULL)
      if (!is.null(remote_parsed)) {
        forward_deps <- c(forward_deps,
                          vapply(remote_parsed, `[[`, "", "package"))
      }
    }
  }
  forward_deps <- unique(forward_deps[nzchar(forward_deps) &
                                      forward_deps != "R"])
} else {
  message("::warning::parse-deps: no DESCRIPTION found at ./ or pkg/; ",
          "skipping forward-dep validation")
}

errors <- character()
if (length(parsed) && length(forward_deps)) {
  for (p in parsed) {
    if (p$package %in% forward_deps) {
      errors <- c(errors, sprintf(
        "  - '%s' targets '%s', which is a forward dependency. The deps block is for revdep refs only; forward-dep overrides belong in DESCRIPTION's Remotes: field.",
        p$ref, p$package
      ))
    }
  }
}

if (length(errors)) {
  message("parse-deps: invalid deps block")
  for (e in errors) message(e)
  quit(status = 1)
}

ref_out <- ""
if (nzchar(pkg_filter) && length(parsed)) {
  target_pkg <- sub("^.*/", "", pkg_filter)
  for (p in parsed) {
    if (identical(p$package, target_pkg)) {
      pull <- if (is.null(p$pull)) "" else p$pull
      commitish <- if (is.null(p$commitish)) "" else p$commitish
      if (nzchar(pull)) {
        ref_out <- sprintf("refs/pull/%s/head", pull)
      } else if (nzchar(commitish) && commitish != "HEAD") {
        ref_out <- commitish
      }
      break
    }
  }
}

# `extra-packages` is base only; deps-block entries are never appended.
out <- c(
  "extra-packages<<EOF",
  base_pkgs,
  "EOF",
  sprintf("ref=%s", ref_out)
)
cat(out, sep = "\n", file = out_path, append = TRUE)
cat("\n", file = out_path, append = TRUE)
