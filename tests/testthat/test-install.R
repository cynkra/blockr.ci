# Source install.R into a local environment for testing
install_env <- local({
  env <- new.env(parent = globalenv())
  path <- system.file("install.R", package = "blockr.ci")
  if (!nzchar(path)) {
    path <- test_path("..", "..", "inst", "install.R")
  }
  source(path, local = env)
  env
})

# Helper: build a mock get_info function from a list
mock_info_fn <- function(info_map) {
  function(repo) {
    info_map[[repo]] %||% list(
      deps = character(),
      remotes = list()
    )
  }
}

# Helper: shorthand for a package info entry
pkg_info <- function(deps = character(),
                     remotes = list()) {
  list(deps = deps, remotes = remotes)
}

# Helper: shorthand for a remote entry
remote <- function(repo, ref = NULL) {
  list(repo = repo, ref = ref)
}

# ── topo_sort ──────────────────────────────────────

test_that("topo_sort handles linear chain", {
  adj <- list(
    a = character(), b = "a", c = "b"
  )
  result <- install_env$topo_sort(adj)
  expect_equal(result, c("a", "b", "c"))
})

test_that("topo_sort handles diamond dependency", {
  adj <- list(
    a = character(),
    b = "a", c = "a",
    d = c("b", "c")
  )
  result <- install_env$topo_sort(adj)
  expect_equal(result[1], "a")
  expect_equal(result[length(result)], "d")
  expect_length(result, 4)
  expect_setequal(result, c("a", "b", "c", "d"))
})

test_that("topo_sort handles single package", {
  adj <- list(a = character())
  expect_equal(install_env$topo_sort(adj), "a")
})

test_that("topo_sort handles independent packages", {
  adj <- list(
    a = character(),
    b = character(),
    c = character()
  )
  result <- install_env$topo_sort(adj)
  expect_length(result, 3)
  expect_setequal(result, c("a", "b", "c"))
})

test_that("topo_sort survives cycle", {
  adj <- list(a = "b", b = "a")
  result <- install_env$topo_sort(adj)
  expect_length(result, 2)
  expect_setequal(result, c("a", "b"))
})

# ── parse_remotes ──────────────────────────────────

test_that("parse_remotes extracts owner/repo", {
  dcf <- matrix(
    "someorg/pkgA, anotherorg/pkgB",
    dimnames = list(NULL, "Remotes")
  )
  result <- install_env$parse_remotes(dcf)
  expect_equal(result, list(
    pkgA = remote("someorg/pkgA"),
    pkgB = remote("anotherorg/pkgB")
  ))
})

test_that("parse_remotes preserves @ref and #PR", {
  dcf <- matrix(
    "org/pkg@feature, org/other#42",
    dimnames = list(NULL, "Remotes")
  )
  result <- install_env$parse_remotes(dcf)
  expect_equal(result, list(
    pkg = remote("org/pkg", "feature"),
    other = remote("org/other", "42")
  ))
})

test_that("parse_remotes skips non-GitHub entries", {
  dcf <- matrix(
    "bioc::BiocPkg, org/real",
    dimnames = list(NULL, "Remotes")
  )
  result <- install_env$parse_remotes(dcf)
  expect_equal(
    result,
    list(real = remote("org/real"))
  )
})

test_that("parse_remotes returns empty when absent", {
  dcf <- matrix(
    "blockr.core",
    dimnames = list(NULL, "Package")
  )
  result <- install_env$parse_remotes(dcf)
  expect_length(result, 0)
})

# ── build_dag ─────────────────────────────────────

test_that("build_dag finds direct registry deps", {
  registry <- c(A = "org/A", B = "org/B")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(deps = c("A", "X")),
    "org/A" = pkg_info(),
    "org/B" = pkg_info()
  ))

  dag <- install_env$build_dag(
    "org/target", registry,
    get_info = get_info
  )
  expect_equal(dag$deps, "A")
})

test_that("build_dag finds transitive registry deps", {
  registry <- c(
    A = "org/A", B = "org/B", C = "org/C"
  )
  get_info <- mock_info_fn(list(
    "org/C" = pkg_info(deps = c("A", "B")),
    "org/B" = pkg_info(deps = "A"),
    "org/A" = pkg_info()
  ))

  dag <- install_env$build_dag(
    "org/C", registry,
    get_info = get_info
  )
  expect_setequal(dag$deps, c("A", "B"))
  expect_true("A" %in% dag$adj[["B"]])
})

test_that("build_dag follows Remotes to find registry deps", {
  registry <- c(A = "org/A", B = "org/B")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = c("A", "X"),
      remotes = list(X = remote("other/X"))
    ),
    "org/A" = pkg_info(),
    "other/X" = pkg_info(deps = "B"),
    "org/B" = pkg_info()
  ))

  dag <- install_env$build_dag(
    "org/target", registry,
    get_info = get_info
  )
  expect_setequal(dag$deps, c("A", "B"))
})

test_that("build_dag computes transitive adj through non-registry nodes", {
  registry <- c(A = "org/A", B = "org/B")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = "A",
      remotes = list(
        X = remote("other/X")
      )
    ),
    "org/A" = pkg_info(
      deps = "X",
      remotes = list(
        X = remote("other/X")
      )
    ),
    "other/X" = pkg_info(deps = "B"),
    "org/B" = pkg_info()
  ))

  dag <- install_env$build_dag(
    "org/target", registry,
    get_info = get_info
  )
  expect_setequal(dag$deps, c("A", "B"))
  # A -> X -> B, so adj[A] should include B
  expect_true("B" %in% dag$adj[["A"]])
})

test_that("build_dag excludes target from deps", {
  registry <- c(A = "org/A")
  get_info <- mock_info_fn(list(
    "org/A" = pkg_info(deps = character())
  ))

  dag <- install_env$build_dag(
    "org/A", registry,
    get_info = get_info
  )
  expect_length(dag$deps, 0)
})

test_that("build_dag returns empty for no registry deps", {
  registry <- c(A = "org/A")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(deps = c("ggplot2"))
  ))

  dag <- install_env$build_dag(
    "org/target", registry,
    get_info = get_info
  )
  expect_length(dag$deps, 0)
})

test_that("build_dag handles circular deps", {
  registry <- c(A = "org/A", B = "org/B")
  get_info <- mock_info_fn(list(
    "org/A" = pkg_info(deps = "B"),
    "org/B" = pkg_info(deps = "A")
  ))

  dag <- install_env$build_dag(
    "org/A", registry,
    get_info = get_info
  )
  expect_true("B" %in% dag$deps)
})

# ── build_dag conflict detection ──────────────────

test_that("build_dag errors on pinned ref for traversed dep", {
  registry <- c(A = "org/A", B = "org/B")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = c("A", "X"),
      remotes = list(
        X = remote("other/X", "feat")
      )
    ),
    "org/A" = pkg_info()
  ))

  expect_error(
    install_env$build_dag(
      "org/target", registry,
      get_info = get_info
    ),
    "pinned to ref"
  )
})

test_that("build_dag errors on conflicting repo sources", {
  registry <- c(A = "org/A")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = "A",
      remotes = list(
        A = remote("other/A")
      )
    )
  ))

  expect_error(
    install_env$build_dag(
      "org/target", registry,
      get_info = get_info
    ),
    "Conflicting sources"
  )
})

test_that("build_dag errors on conflicting refs", {
  registry <- c(A = "org/A")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = c("X", "Y"),
      remotes = list(
        X = remote("other/X"),
        Y = remote("other/Y")
      )
    ),
    "other/X" = pkg_info(
      remotes = list(
        Z = remote("org/Z", "branch-a")
      )
    ),
    "other/Y" = pkg_info(
      remotes = list(
        Z = remote("org/Z", "branch-b")
      )
    )
  ))

  expect_error(
    install_env$build_dag(
      "org/target", registry,
      get_info = get_info
    ),
    "Conflicting refs"
  )
})

test_that("build_dag allows matching Remotes for registry pkg", {
  registry <- c(A = "org/A")
  get_info <- mock_info_fn(list(
    "org/target" = pkg_info(
      deps = "A",
      remotes = list(
        A = remote("org/A")
      )
    ),
    "org/A" = pkg_info()
  ))

  dag <- install_env$build_dag(
    "org/target", registry,
    get_info = get_info
  )
  expect_equal(dag$deps, "A")
})

# ── fetch_registry (live) ─────────────────────────

test_that("fetch_registry returns named character vector", {
  skip_if_offline()
  registry <- install_env$fetch_registry()
  expect_type(registry, "character")
  expect_true(length(registry) > 0)
  expect_true(all(nzchar(names(registry))))
  expect_true("blockr.core" %in% names(registry))
})

# ── fetch_pkg_info (live) ─────────────────────────

test_that("fetch_pkg_info returns deps and remotes", {
  skip_if_offline()
  info <- install_env$fetch_pkg_info(
    "BristolMyersSquibb/blockr.core"
  )
  expect_type(info, "list")
  expect_true("deps" %in% names(info))
  expect_true("remotes" %in% names(info))
  expect_type(info$deps, "character")
  expect_true(length(info$deps) > 0)
  expect_true("shiny" %in% info$deps)
})
