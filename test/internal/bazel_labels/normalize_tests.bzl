"""Tests for `bazel_labels.normalize`"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load(
    "//xcodeproj/internal:bazel_labels.bzl",
    "make_bazel_labels",
)

# buildifier: disable=bzl-visibility
load(
    "//xcodeproj/internal:workspace_name_resolvers.bzl",
    "make_stub_workspace_name_resolvers",
)

bazel_labels = make_bazel_labels(
    workspace_name_resolvers = make_stub_workspace_name_resolvers(
        repo_name = "@",
        pkg_name = "Sources/Foo",
    ),
)

def _main_repo_prefix():
    return str(Label("@//:BUILD")).partition("//")[0]

def _external_repo_prefix():
    return str(Label("@_repo//:BUILD")).partition("_")[0]

def _relative_label_test(ctx):
    env = unittest.begin(ctx)

    value = ":chicken"
    actual = bazel_labels.normalize(value)
    expected = _main_repo_prefix() + "//Sources/Foo:chicken"
    asserts.equals(env, expected, actual)

    return unittest.end(env)

relative_label_test = unittest.make(_relative_label_test)

def _absolute_label_with_repo_name_test(ctx):
    env = unittest.begin(ctx)

    value = "@my_dep//Sources/Foo:chicken"
    actual = bazel_labels.normalize(value)
    expected = _external_repo_prefix() + "my_dep//Sources/Foo:chicken"
    asserts.equals(env, expected, actual)

    return unittest.end(env)

absolute_label_with_repo_name_test = unittest.make(_absolute_label_with_repo_name_test)

def _absolute_label_without_repo_name_test(ctx):
    env = unittest.begin(ctx)

    value = "//Sources/Foo:chicken"
    actual = bazel_labels.normalize(value)
    expected = _main_repo_prefix() + "//Sources/Foo:chicken"
    asserts.equals(env, expected, actual)

    return unittest.end(env)

absolute_label_without_repo_name_test = unittest.make(_absolute_label_without_repo_name_test)

def normalize_test_suite(name):
    return unittest.suite(
        name,
        relative_label_test,
        absolute_label_with_repo_name_test,
        absolute_label_without_repo_name_test,
    )
