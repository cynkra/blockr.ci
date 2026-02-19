# install.R — base-R-only installer for blockr.* packages
#
# Sourced at runtime by per-repo install scripts on GitHub Pages.
# No external R packages required.

fetch_registry <- function() {
  base <- "https://raw.githubusercontent.com"
  url <- paste0(
    base, "/cynkra/blockr.ci/main/",
    ".github/actions/registry.txt"
  )
  lines <- readLines(url, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  parts <- strsplit(lines, "=", fixed = TRUE)
  vals <- vapply(parts, `[[`, character(1), 2L)
  names(vals) <- vapply(parts, `[[`, character(1), 1L)
  vals
}

fetch_pkg_info <- function(repo) {
  base <- "https://raw.githubusercontent.com"
  url <- sprintf("%s/%s/HEAD/DESCRIPTION", base, repo)
  tmp <- tempfile(fileext = ".dcf")
  on.exit(unlink(tmp), add = TRUE)
  download.file(url, tmp, quiet = TRUE)
  dcf <- read.dcf(tmp)

  pkg <- dcf[, "Package"]
  which <- c("Depends", "Imports", "Suggests")
  for (field in which) {
    if (!field %in% colnames(dcf)) {
      dcf <- cbind(dcf, structure(
        NA_character_,
        dim = c(1L, 1L),
        dimnames = list(NULL, field)
      ))
    }
  }
  dep_list <- tools::package_dependencies(
    pkg, db = dcf, which = which
  )
  deps <- dep_list[[pkg]] %||% character()

  remotes <- parse_remotes(dcf)

  list(deps = deps, remotes = remotes)
}

parse_remotes <- function(dcf) {
  if (!"Remotes" %in% colnames(dcf)) {
    return(list())
  }
  raw <- dcf[, "Remotes"]
  if (is.na(raw) || !nzchar(raw)) {
    return(list())
  }
  entries <- trimws(strsplit(raw, "[,\n]")[[1]])
  entries <- entries[nzchar(entries)]
  result <- list()
  for (entry in entries) {
    if (grepl("::", entry, fixed = TRUE)) next
    ref <- NULL
    if (grepl("@", entry, fixed = TRUE)) {
      ref <- sub(".*@", "", entry)
      repo <- sub("@.*", "", entry)
    } else if (grepl("#", entry, fixed = TRUE)) {
      ref <- sub(".*#", "", entry)
      repo <- sub("#.*", "", entry)
    } else {
      repo <- entry
    }
    if (!grepl("/", repo, fixed = TRUE)) next
    parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
    pkg_name <- parts[length(parts)]
    result[[pkg_name]] <- list(
      repo = repo, ref = ref
    )
  }
  result
}

build_dag <- function(repo, registry,
                      get_info = fetch_pkg_info) {
  url_map <- registry
  cache <- list()
  ref_pins <- list()

  traverse <- function(current_repo) {
    if (current_repo %in% names(cache)) return()
    info <- get_info(current_repo)
    cache[[current_repo]] <<- info

    for (nm in names(info$remotes)) {
      remote <- info$remotes[[nm]]
      if (nm %in% names(url_map)) {
        if (remote$repo != url_map[[nm]]) {
          stop(sprintf(
            paste0(
              "Conflicting sources for ",
              "'%s': '%s' vs '%s'"
            ),
            nm, url_map[[nm]], remote$repo
          ))
        }
      } else {
        url_map[[nm]] <<- remote$repo
      }
      if (!is.null(remote$ref)) {
        prev <- ref_pins[[nm]]
        if (!is.null(prev) &&
              prev != remote$ref) {
          stop(sprintf(
            paste0(
              "Conflicting refs for '%s'",
              ": '%s' vs '%s'"
            ),
            nm, prev, remote$ref
          ))
        }
        ref_pins[[nm]] <<- remote$ref
      }
    }

    for (dep in info$deps) {
      if (dep %in% names(url_map)) {
        if (dep %in% names(ref_pins)) {
          stop(sprintf(
            paste0(
              "Package '%s' is pinned to",
              " ref '%s' via Remotes but",
              " this installer always ",
              "uses the default branch"
            ),
            dep, ref_pins[[dep]]
          ))
        }
        traverse(url_map[[dep]])
      }
    }
  }

  traverse(repo)

  all_deps <- unique(unlist(
    lapply(cache, `[[`, "deps")
  ))
  registry_hits <- intersect(all_deps, names(registry))

  target_name <- names(registry)[registry == repo]
  registry_hits <- setdiff(registry_hits, target_name)

  adj <- build_registry_adj(
    registry_hits, url_map, cache
  )

  list(
    deps = registry_hits,
    adj = adj,
    cache = cache,
    url_map = url_map
  )
}

build_registry_adj <- function(registry_hits,
                               url_map, cache) {
  trans_deps <- function(pkg_name) {
    visited <- character()
    stack <- pkg_name
    while (length(stack)) {
      current <- stack[1]
      stack <- stack[-1]
      if (current %in% visited) next
      visited <- c(visited, current)
      if (current %in% names(url_map)) {
        r <- url_map[[current]]
        if (r %in% names(cache)) {
          info <- cache[[r]]
          stack <- c(
            stack,
            setdiff(info$deps, visited)
          )
        }
      }
    }
    intersect(
      setdiff(visited, pkg_name),
      registry_hits
    )
  }

  adj <- list()
  for (pkg in registry_hits) {
    adj[[pkg]] <- trans_deps(pkg)
  }
  adj
}

topo_sort <- function(adj) {
  pkg_names <- names(adj)
  order <- character()
  state <- rep("unvisited", length(pkg_names))
  names(state) <- pkg_names

  visit <- function(node) {
    if (state[[node]] == "visited") return()
    if (state[[node]] == "visiting") return()
    state[[node]] <<- "visiting"
    for (dep in adj[[node]]) {
      visit(dep)
    }
    state[[node]] <<- "visited"
    order <<- c(order, node)
  }

  for (pkg in pkg_names) visit(pkg)
  order
}

install_from_github <- function(repo) {
  url <- sprintf(
    "https://github.com/%s/archive/refs/heads/main.tar.gz",
    repo
  )
  tmp <- tempfile(fileext = ".tar.gz")
  on.exit(unlink(tmp), add = TRUE)
  download.file(url, tmp, quiet = TRUE, mode = "wb")
  install.packages(tmp, repos = NULL, type = "source")
}

install_blockr <- function(repo) {
  message("-- Fetching blockr registry")
  registry <- fetch_registry()

  message("-- Building dependency graph for ", repo)
  dag <- build_dag(repo, registry)
  dep_names <- dag$deps

  if (length(dep_names)) {
    dep_names <- topo_sort(dag$adj)
    message(
      "-- Install order: ",
      paste(dep_names, collapse = " -> ")
    )
  }

  for (pkg in dep_names) {
    dep_repo <- registry[[pkg]]
    message(
      "-- Installing registry dep: ",
      pkg, " (", dep_repo, ")"
    )
    info <- dag$cache[[dep_repo]]
    skip <- c(
      names(registry), "R", "base",
      rownames(installed.packages())
    )
    cran_deps <- info$deps[!info$deps %in% skip]
    if (length(cran_deps)) {
      message(
        "   Installing CRAN deps: ",
        paste(cran_deps, collapse = ", ")
      )
      install.packages(cran_deps)
    }
    install_from_github(dep_repo)
  }

  message("-- Installing target: ", repo)
  info <- dag$cache[[repo]]
  skip <- c(
    names(registry), "R", "base",
    rownames(installed.packages())
  )
  cran_deps <- info$deps[!info$deps %in% skip]
  if (length(cran_deps)) {
    message(
      "   Installing CRAN deps: ",
      paste(cran_deps, collapse = ", ")
    )
    install.packages(cran_deps)
  }
  install_from_github(repo)

  message("-- Done!")
}
