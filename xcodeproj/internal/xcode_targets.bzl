"""Module containing functions dealing with the `Target` DTO."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:structs.bzl", "structs")
load(":collections.bzl", "set_if_true", "uniq")
load(
    ":files.bzl",
    "build_setting_path",
    "file_path",
    "file_path_to_dto",
    "normalized_file_path",
    "quote_if_needed",
)
load(":lldb_contexts.bzl", "lldb_contexts")
load(":platform.bzl", "platform_info")

def _make_xcode_target(
        *,
        id,
        name,
        label,
        configuration,
        compile_target = None,
        package_bin_dir,
        platform,
        product,
        is_testonly = False,
        is_swift,
        test_host = None,
        build_settings,
        search_paths = None,
        modulemaps,
        swiftmodules,
        inputs,
        linker_inputs = None,
        infoplist = None,
        watch_application = None,
        extensions = [],
        app_clips = [],
        dependencies,
        transitive_dependencies,
        outputs,
        lldb_context = None,
        xcode_required_targets = depset()):
    """Creates the internal data structure of the `xcode_targets` module.

    Args:
        id: A unique identifier. No two Xcode targets will have the same `id`.
            This won't be user facing, the generator will use other fields to
            generate a unique name for a target.
        name: The base name that the Xcode target should use. Multiple
            Xcode targets can have the same name; the generator will
            disambiguate them.
        label: The `Label` of the `Target`.
        configuration: The configuration of the `Target`.
        compile_target: The `xcode_target` that was merged into this target.
        package_bin_dir: The package directory for the `Target` within
            `ctx.bin_dir`.
        platform: The value returned from `process_platform`.
        product: The value returned from `process_product`.
        is_testonly: Whether the `Target` has `testonly = True` set.
        is_swift: Whether the target compiles Swift code.
        test_host: The `id` of the target that is the test host for this
            target, or `None` if this target does not have a test host.
        build_settings: A `dict` of Xcode build settings for the target.
        search_paths: A value returned from `target_search_paths.make`, or
            `None`.
        modulemaps: The value returned from `process_modulemaps`.
        swiftmodules: The value returned from `process_swiftmodules`.
        inputs: The value returned from `input_files.collect`.
        linker_inputs: A value returned from `linker_input_files.collect` or
            `None`.
        infoplist: A `File` or `None`.
        watch_application: The `id` of the watch application target that should
            be embedded in this target, or `None`.
        extensions: A `list` of `id`s of application extension targets that
            should be embedded in this target.
        app_clips: A `list` of `id`s of app clip targets that should be embedded
            in this target.
        dependencies: A `depset` of `id`s of targets that this target depends
            on.
        transitive_dependencies: A `depset` of `id`s of all transitive targets
            that this target depends on.
        outputs: A value returned from `output_files.collect`.
        lldb_context: A value returned from `lldb_contexts.collect`.
        xcode_required_targets: A `depset` of values returned from
            `xcode_targets.make`, which represent targets that are required in
            BwX mode.

    Returns:
        A mostly opaque `struct` that can be passed to `xcode_targets.to_dto`.
    """
    return struct(
        _compile_target = compile_target,
        _package_bin_dir = package_bin_dir,
        _is_testonly = is_testonly,
        _test_host = test_host,
        _build_settings = struct(**build_settings),
        _search_paths = search_paths,
        _modulemaps = modulemaps,
        _swiftmodules = tuple(swiftmodules),
        _watch_application = watch_application,
        _extensions = tuple(extensions),
        _app_clips = tuple(app_clips),
        _dependencies = dependencies,
        _lldb_context = lldb_context,
        id = id,
        name = name,
        label = label,
        configuration = configuration,
        platform = platform,
        product = (
            _to_xcode_target_product(product) if not compile_target else product
        ),
        linker_inputs = (
            _to_xcode_target_linker_inputs(linker_inputs) if not compile_target else linker_inputs
        ),
        inputs = (
            _to_xcode_target_inputs(inputs) if not compile_target else inputs
        ),
        is_swift = is_swift,
        outputs = (
            _to_xcode_target_outputs(outputs) if not compile_target else outputs
        ),
        infoplist = infoplist,
        transitive_dependencies = transitive_dependencies,
        xcode_required_targets = xcode_required_targets,
    )

def _to_xcode_target_inputs(inputs):
    return struct(
        srcs = inputs.srcs,
        non_arc_srcs = inputs.non_arc_srcs,
        hdrs = inputs.hdrs,
        pch = inputs.pch,
        entitlements = inputs.entitlements,
        resources = inputs.resources,
        resource_bundle_dependencies = inputs.resource_bundle_dependencies,
        generated = inputs.generated,
        indexstores = inputs.indexstores,
        unfocused_generated_compiling = inputs.unfocused_generated_compiling,
        unfocused_generated_indexstores = (
            inputs.unfocused_generated_indexstores
        ),
        unfocused_generated_linking = inputs.unfocused_generated_linking,
        compiling_output_group_name = inputs.compiling_output_group_name,
        indexstores_output_group_name = inputs.indexstores_output_group_name,
        linking_output_group_name = inputs.linking_output_group_name,
    )

def _to_xcode_target_linker_inputs(linker_inputs):
    if not linker_inputs:
        return None

    top_level_values = linker_inputs._top_level_values
    if not top_level_values:
        return None

    return struct(
        dynamic_frameworks = top_level_values.dynamic_frameworks,
        link_args = top_level_values.link_args,
        link_args_inputs = top_level_values.link_args_inputs,
        static_libraries = top_level_values.static_libraries,
        static_frameworks = top_level_values.static_frameworks,
    )

def _to_xcode_target_outputs(outputs):
    direct_outputs = outputs.direct_outputs

    swiftmodule = None
    swift_generated_header = None
    if direct_outputs:
        swift = direct_outputs.swift
        if swift:
            swiftmodule = swift.module.swiftmodule
            if swift.generated_header:
                swift_generated_header = swift.generated_header

    return struct(
        linking_output_group_name = outputs.linking_output_group_name,
        product_file = (
            direct_outputs.product if direct_outputs else None
        ),
        product_path = (
            direct_outputs.product_path if direct_outputs else None
        ),
        products_output_group_name = outputs.products_output_group_name,
        swiftmodule = swiftmodule,
        swift_generated_header = swift_generated_header,
        transitive_infoplists = outputs.transitive_infoplists,
    )

def _to_xcode_target_product(product):
    return struct(
        name = product.name,
        type = product.type,
        file = product.file,
        file_path = product.file_path,
        executable = product.executable,
        executable_name = product.executable_name,
        additional_product_files = tuple(),
        framework_files = product.framework_files,
        _additional_files = product.framework_files,
        _is_resource_bundle = product.is_resource_bundle,
    )

def _merge_xcode_target(*, src, dest):
    """Creates a new `xcode_target` by merging the values of `src` into `dest`.

    Args:
        src: The `xcode_target` to merge into `dest`.
        dest: The `xcode_target` being merged into.

    Returns:
        A value as returned by `xcode_targets.make`.
    """

    build_settings = dict(structs.to_dict(src._build_settings))
    build_settings = dicts.add(
        structs.to_dict(dest._build_settings),
        build_settings,
    )

    return _make_xcode_target(
        id = dest.id,
        name = dest.name,
        label = dest.label,
        configuration = dest.configuration,
        compile_target = src,
        package_bin_dir = dest._package_bin_dir,
        platform = src.platform,
        product = _merge_xcode_target_product(
            src = src.product,
            dest = dest.product,
        ),
        is_testonly = dest._is_testonly,
        is_swift = src.is_swift,
        test_host = dest._test_host,
        build_settings = build_settings,
        search_paths = dest._search_paths,
        modulemaps = src._modulemaps,
        swiftmodules = src._swiftmodules,
        inputs = _merge_xcode_target_inputs(
            src = src.inputs,
            dest = dest.inputs,
        ),
        linker_inputs = dest.linker_inputs,
        infoplist = dest.infoplist,
        watch_application = dest._watch_application,
        extensions = dest._extensions,
        app_clips = dest._app_clips,
        dependencies = depset(
            transitive = [dest._dependencies, src._dependencies],
        ),
        transitive_dependencies = dest.transitive_dependencies,
        outputs = _merge_xcode_target_outputs(
            src = src.outputs,
            dest = dest.outputs,
        ),
        lldb_context = dest._lldb_context,
        xcode_required_targets = dest.xcode_required_targets,
    )

def _merge_xcode_target_inputs(*, src, dest):
    return struct(
        srcs = src.srcs,
        non_arc_srcs = src.non_arc_srcs,
        hdrs = dest.hdrs,
        pch = src.pch,
        entitlements = dest.entitlements,
        resources = dest.resources,
        resource_bundle_dependencies = dest.resource_bundle_dependencies,
        generated = dest.generated,
        indexstores = dest.indexstores,
        unfocused_generated_compiling = dest.unfocused_generated_compiling,
        unfocused_generated_indexstores = (
            dest.unfocused_generated_indexstores
        ),
        unfocused_generated_linking = dest.unfocused_generated_linking,
        compiling_output_group_name = dest.compiling_output_group_name,
        indexstores_output_group_name = dest.indexstores_output_group_name,
        linking_output_group_name = dest.linking_output_group_name,
    )

def _merge_xcode_target_outputs(*, src, dest):
    return struct(
        linking_output_group_name = dest.linking_output_group_name,
        swiftmodule = src.swiftmodule,
        swift_generated_header = src.swift_generated_header,
        product_file = dest.product_file,
        product_path = dest.product_path,
        products_output_group_name = dest.products_output_group_name,
        transitive_infoplists = dest.transitive_infoplists,
    )

def _merge_xcode_target_product(*, src, dest):
    return struct(
        name = dest.name,
        type = dest.type,
        file = dest.file,
        file_path = dest.file_path,
        executable = dest.executable,
        executable_name = dest.executable_name,
        framework_files = depset(
            transitive = [dest.framework_files, src.framework_files],
        ),
        additional_product_files = tuple([src.file]),
        _additional_files = depset(
            [src.file],
            transitive = [dest._additional_files, src._additional_files],
        ),
        _is_resource_bundle = dest._is_resource_bundle,
    )

def _prepend_array_build_setting(*, build_settings, key, values):
    existing = build_settings.get(key, None)
    if existing:
        values.extend(existing)
    set_if_true(build_settings, key, values)

def _set_bazel_outputs_product(
        *,
        build_mode,
        build_settings,
        xcode_target):
    if build_mode != "bazel":
        return

    path = xcode_target.outputs.product_path
    if not path:
        return

    build_settings["BAZEL_OUTPUTS_PRODUCT"] = path

def _set_search_paths(
        *,
        build_settings,
        search_paths_intermediate,
        xcode_target):
    if not xcode_target.is_swift:
        _prepend_array_build_setting(
            build_settings = build_settings,
            key = "USER_HEADER_SEARCH_PATHS",
            values = [
                quote_if_needed(path)
                for path in search_paths_intermediate.quote_includes
            ],
        )
        _prepend_array_build_setting(
            build_settings = build_settings,
            key = "HEADER_SEARCH_PATHS",
            values = [
                quote_if_needed(path)
                for path in search_paths_intermediate.includes
            ],
        )
        _prepend_array_build_setting(
            build_settings = build_settings,
            key = "SYSTEM_HEADER_SEARCH_PATHS",
            values = [
                quote_if_needed(path)
                for path in search_paths_intermediate.system_includes
            ],
        )

def _set_preview_framework_paths(
        *,
        build_mode,
        build_settings,
        linker_products_map,
        xcode_target):
    if (build_mode == "xcode" or
        xcode_target.product.type != "com.apple.product-type.framework"):
        return

    def _map_framework(file):
        path = build_setting_path(
            file = file,
            path = file.dirname,
        )
        return '"{}"'.format(linker_products_map.get(path, path))

    build_settings["PREVIEW_FRAMEWORK_PATHS"] = [
        _map_framework(file)
        for file in xcode_target.linker_inputs.dynamic_frameworks
    ]

_PREVIEWS_ENABLED_PRODUCT_TYPES = {
    "com.apple.product-type.application": None,
    "com.apple.product-type.application.on-demand-install-capable": None,
    "com.apple.product-type.app-extension": None,
    "com.apple.product-type.app-extension.messages": None,
    "com.apple.product-type.extensionkit-extension": None,
    "com.apple.product-type.framework": None,
    "com.apple.product-type.bundle.ui-testing": None,
    "com.apple.product-type.bundle.unit-test": None,
    "com.apple.product-type.tv-app-extension": None,
    "com.apple.product-type.application.watchapp": None,
    "com.apple.product-type.application.watchapp2": None,
    "com.apple.product-type.watchkit-extension": None,
    "com.apple.product-type.watchkit2-extension": None,
}

def _set_swift_include_paths(
        *,
        build_settings,
        xcode_generated_paths,
        xcode_target):
    if not xcode_target.is_swift:
        return

    def _handle_swiftmodule_path(file):
        path = file.path
        bs_path = xcode_generated_paths.get(path)
        if not bs_path:
            bs_path = path
        include_path = paths.dirname(bs_path)

        if include_path.find(" ") != -1:
            include_path = '"{}"'.format(include_path)

        return include_path

    includes = uniq([
        _handle_swiftmodule_path(file)
        for file in xcode_target._swiftmodules
    ])

    swiftmodule = xcode_target.outputs.swiftmodule
    if (swiftmodule and
        xcode_target.product.type in _PREVIEWS_ENABLED_PRODUCT_TYPES):
        build_settings["PREVIEWS_SWIFT_INCLUDE_PATH__"] = ""
        build_settings["PREVIEWS_SWIFT_INCLUDE_PATH__NO"] = ""
        build_settings["PREVIEWS_SWIFT_INCLUDE_PATH__YES"] = (
            _handle_swiftmodule_path(swiftmodule)
        )
        includes.insert(
            0,
            "$(PREVIEWS_SWIFT_INCLUDE_PATH__$(ENABLE_PREVIEWS))",
        )

    set_if_true(build_settings, "SWIFT_INCLUDE_PATHS", " ".join(includes))

def _generated_framework_search_paths(
        *,
        build_mode,
        search_paths_intermediate,
        xcode_generated_paths,
        xcode_target):
    if build_mode != "xcode":
        return {}

    if xcode_target.linker_inputs:
        frameworks = xcode_target.linker_inputs.dynamic_frameworks
    else:
        frameworks = []

    framework_search_paths = {}
    for file in frameworks:
        framework_path = file.dirname
        search_path = paths.dirname(framework_path)
        xcode_generated_path = xcode_generated_paths.get(framework_path)
        if xcode_generated_path:
            framework_search_paths.setdefault(search_path, {})["x"] = (
                paths.dirname(xcode_generated_path)
            )
        else:
            # Since we use `framework_search_paths` in `link.params`, we need to
            # fully qualify the paths
            framework_search_paths.setdefault(search_path, {})["b"] = (
                build_setting_path(file = file, path = search_path)
            )

    ordered_framework_search_paths = {}
    for search_path in search_paths_intermediate.framework_includes:
        search_paths = framework_search_paths.pop(search_path, None)
        if search_paths:
            ordered_framework_search_paths[search_path] = search_paths
            continue

        # Imported frameworks
        ordered_framework_search_paths.setdefault(search_path, {})["b"] = (
            build_setting_path(path = search_path)
        )

    # Add remaining items from `framework_search_paths`, for linker only paths
    for search_path, search_paths in framework_search_paths.items():
        ordered_framework_search_paths[search_path] = search_paths

    return ordered_framework_search_paths

def _xcode_target_to_dto(
        xcode_target,
        *,
        additional_scheme_target_ids = None,
        build_mode,
        ctx,
        include_lldb_context,
        is_fixture,
        is_unfocused_dependency = False,
        link_params_processor,
        linker_products_map,
        params_index,
        should_include_outputs,
        unfocused_targets = {},
        target_merges = {},
        xcode_generated_paths,
        xcode_generated_paths_file):
    inputs = xcode_target.inputs

    dto = {
        "name": xcode_target.name,
        "label": str(xcode_target.label),
        "configuration": xcode_target.configuration,
        "package_bin_dir": xcode_target._package_bin_dir,
        "platform": platform_info.to_dto(xcode_target.platform),
        "product": _product_to_dto(xcode_target.product),
    }

    if xcode_target._compile_target:
        dto["compile_target"] = {
            "id": xcode_target._compile_target.id,
            "name": xcode_target._compile_target.name,
        }

    if xcode_target._is_testonly:
        dto["is_testonly"] = True

    if not xcode_target.is_swift:
        dto["is_swift"] = False

    if is_unfocused_dependency:
        dto["is_unfocused_dependency"] = True

    if xcode_target._test_host not in unfocused_targets:
        set_if_true(dto, "test_host", xcode_target._test_host)

    if xcode_target._watch_application not in unfocused_targets:
        set_if_true(dto, "watch_application", xcode_target._watch_application)

    if include_lldb_context:
        set_if_true(
            dto,
            "lldb_context",
            lldb_contexts.to_dto(
                xcode_target._lldb_context,
                xcode_generated_paths = xcode_generated_paths,
            ),
        )

    search_paths_intermediate = _search_paths_to_intermediate(
        search_paths = xcode_target._search_paths,
        compile_target = xcode_target._compile_target,
    )

    generated_framework_search_paths = _generated_framework_search_paths(
        build_mode = build_mode,
        search_paths_intermediate = search_paths_intermediate,
        xcode_generated_paths = xcode_generated_paths,
        xcode_target = xcode_target,
    )

    linker_inputs_dto, link_params = _linker_inputs_to_dto(
        ctx = ctx,
        compile_target = xcode_target._compile_target,
        generated_framework_search_paths = generated_framework_search_paths,
        is_framework = (
            xcode_target.product.type == "com.apple.product-type.framework"
        ),
        link_params_processor = link_params_processor,
        linker_inputs = xcode_target.linker_inputs,
        name = xcode_target.name,
        params_index = params_index,
        platform = xcode_target.platform,
        xcode_generated_paths_file = xcode_generated_paths_file,
    )

    set_if_true(
        dto,
        "build_settings",
        _build_settings_to_dto(
            build_mode = build_mode,
            is_fixture = is_fixture,
            linker_products_map = linker_products_map,
            search_paths_intermediate = search_paths_intermediate,
            xcode_generated_paths = xcode_generated_paths,
            xcode_target = xcode_target,
        ),
    )

    set_if_true(
        dto,
        "search_paths",
        _search_paths_intermediate_to_dto(search_paths_intermediate),
    )
    set_if_true(
        dto,
        "has_modulemaps",
        bool(xcode_target._modulemaps),
    )
    set_if_true(
        dto,
        "resource_bundle_dependencies",
        [
            id
            for id in inputs.resource_bundle_dependencies.to_list()
            if id not in unfocused_targets
        ],
    )
    set_if_true(dto, "inputs", _inputs_to_dto(inputs))
    set_if_true(
        dto,
        "linker_inputs",
        linker_inputs_dto,
    )
    set_if_true(
        dto,
        "link_params",
        file_path_to_dto(file_path(link_params)),
    )
    set_if_true(
        dto,
        "info_plist",
        file_path_to_dto(file_path(xcode_target.infoplist)),
    )
    set_if_true(
        dto,
        "extensions",
        [
            id
            for id in xcode_target._extensions
            if id not in unfocused_targets
        ],
    )
    set_if_true(
        dto,
        "app_clips",
        [
            id
            for id in xcode_target._app_clips
            if id not in unfocused_targets
        ],
    )

    if should_include_outputs:
        set_if_true(dto, "outputs", _outputs_to_dto(xcode_target.outputs))

    set_if_true(
        dto,
        "additional_scheme_targets",
        additional_scheme_target_ids,
    )

    replaced_dependencies = []

    def _handle_dependency(id):
        merged_dependency = target_merges.get(id, None)
        if merged_dependency:
            dependency = merged_dependency[0]
            replaced_dependencies.append(dependency)
        else:
            dependency = id
        return dependency

    set_if_true(
        dto,
        "dependencies",
        [
            _handle_dependency(id)
            for id in xcode_target._dependencies.to_list()
            if (id not in unfocused_targets and
                # TODO: Move dependency filtering here (out of the generator)
                # In BwX mode there can only be one merge destination
                target_merges.get(id, [id])[0] != xcode_target.id)
        ],
    )

    return dto, replaced_dependencies, link_params

def _build_settings_to_dto(
        *,
        build_mode,
        is_fixture,
        linker_products_map,
        search_paths_intermediate,
        xcode_generated_paths,
        xcode_target):
    build_settings = structs.to_dict(xcode_target._build_settings)
    _set_bazel_outputs_product(
        build_mode = build_mode,
        build_settings = build_settings,
        xcode_target = xcode_target,
    )
    _set_preview_framework_paths(
        build_mode = build_mode,
        build_settings = build_settings,
        linker_products_map = linker_products_map,
        xcode_target = xcode_target,
    )
    _set_search_paths(
        build_settings = build_settings,
        search_paths_intermediate = search_paths_intermediate,
        xcode_target = xcode_target,
    )
    _set_swift_include_paths(
        build_settings = build_settings,
        xcode_generated_paths = xcode_generated_paths,
        xcode_target = xcode_target,
    )

    if is_fixture:
        # Until we no longer support Bazel 5, we need to remove the
        # `BAZEL_CURRENT_REPOSITORY` define so Bazel 5 and 6 have the same
        # fixture
        local_defines = []
        for local_define in build_settings.pop(
            "GCC_PREPROCESSOR_DEFINITIONS",
            [],
        ):
            if local_define.startswith("BAZEL_CURRENT_REPOSITORY"):
                continue
            local_defines.append(local_define)
        set_if_true(
            build_settings,
            "GCC_PREPROCESSOR_DEFINITIONS",
            local_defines,
        )

    return build_settings

def _inputs_to_dto(inputs):
    """Generates a target DTO value for inputs.

    Args:
        inputs: A value returned from `input_files.to_xcode_target_inputs`.

    Returns:
        A `dict` containing the following elements:

        *   `srcs`: A `list` of `FilePath`s for `srcs`.
        *   `non_arc_srcs`: A `list` of `FilePath`s for `non_arc_srcs`.
        *   `hdrs`: A `list` of `FilePath`s for `hdrs`.
        *   `pch`: An optional `FilePath` for `pch`.
        *   `resources`: A `list` of `FilePath`s for `resources`.
        *   `entitlements`: An optional `FilePath` for `entitlements`.
    """
    ret = {}

    def _process_attr(attr):
        value = getattr(inputs, attr)
        if value:
            ret[attr] = [
                file_path_to_dto(file_path(file))
                for file in value.to_list()
            ]

    _process_attr("srcs")
    _process_attr("non_arc_srcs")
    _process_attr("hdrs")

    if inputs.pch:
        ret["pch"] = file_path_to_dto(file_path(inputs.pch))

    if inputs.entitlements:
        ret["entitlements"] = file_path_to_dto(file_path(inputs.entitlements))

    if inputs.resources:
        set_if_true(
            ret,
            "resources",
            [file_path_to_dto(fp) for fp in inputs.resources.to_list()],
        )

    return ret

def _linker_inputs_to_dto(
        linker_inputs,
        *,
        ctx,
        compile_target,
        generated_framework_search_paths,
        is_framework,
        link_params_processor,
        name,
        params_index,
        platform,
        xcode_generated_paths_file):
    if not linker_inputs:
        return ({}, None)

    if compile_target:
        avoid_library = compile_target.product.file
    else:
        avoid_library = None

    ret = {}
    set_if_true(
        ret,
        "dynamic_frameworks",
        [
            file_path_to_dto(file_path(file, path = file.dirname))
            for file in linker_inputs.dynamic_frameworks
        ],
    )

    if linker_inputs.link_args:
        generated_framework_search_paths_file = ctx.actions.declare_file(
            "{}-params/{}.{}.generated_framework_search_paths.json".format(
                ctx.attr.name,
                name,
                params_index,
            ),
        )
        ctx.actions.write(
            output = generated_framework_search_paths_file,
            content = json.encode(generated_framework_search_paths),
        )

        link_params = ctx.actions.declare_file(
            "{}-params/{}.{}.link.params".format(
                ctx.attr.name,
                name,
                params_index,
            ),
        )

        args = ctx.actions.args()
        args.add(xcode_generated_paths_file)
        args.add(generated_framework_search_paths_file)
        args.add("1" if is_framework else "0")
        args.add(avoid_library.path if avoid_library else "")
        args.add(platform_info.to_swift_triple(platform))
        args.add(link_params)

        ctx.actions.run(
            executable = link_params_processor,
            arguments = [args] + linker_inputs.link_args,
            mnemonic = "ProcessLinkParams",
            progress_message = "Generating %{output}",
            inputs = (
                [
                    xcode_generated_paths_file,
                    generated_framework_search_paths_file,
                ] + list(linker_inputs.link_args_inputs)
            ),
            outputs = [link_params],
        )
    else:
        link_params = None

    return (ret, link_params)

def _outputs_to_dto(outputs):
    dto = {}

    if outputs.product_file:
        dto["p"] = True

    if outputs.swiftmodule:
        dto["s"] = _swift_to_dto(outputs)

    return dto

def _product_to_dto(product):
    return {
        "additional_paths": [
            file_path_to_dto(normalized_file_path(file))
            for file in product._additional_files.to_list()
        ],
        "executable_name": product.executable_name,
        "is_resource_bundle": product._is_resource_bundle,
        "name": product.name,
        "path": file_path_to_dto(product.file_path),
        "type": product.type,
    }

def _search_paths_to_intermediate(search_paths, *, compile_target):
    compile_search_paths = search_paths
    if search_paths:
        compilation_providers = search_paths._compilation_providers
    else:
        compilation_providers = None

    if compilation_providers:
        cc_info = compilation_providers._cc_info
    else:
        cc_info = None

    if compile_target:
        compile_search_paths = compile_target._search_paths
        merged_compilation_providers = (
            compile_target._search_paths._compilation_providers
        )
        if merged_compilation_providers:
            cc_info = merged_compilation_providers._cc_info
        else:
            cc_info = None

    if cc_info:
        opts_search_paths = compile_search_paths._opts_search_paths
        includes = opts_search_paths.includes
        quote_includes = opts_search_paths.quote_includes
        system_includes = opts_search_paths.system_includes
        framework_includes = opts_search_paths.framework_includes
    else:
        quote_includes = []
        includes = []
        system_includes = []
        framework_includes = []

    return struct(
        quote_includes = quote_includes,
        includes = includes,
        system_includes = system_includes,
        framework_includes = framework_includes,
    )

def _search_paths_intermediate_to_dto(search_paths_intermediate):
    dto = {
        "has_includes": bool(search_paths_intermediate.quote_includes or
                             search_paths_intermediate.includes or
                             search_paths_intermediate.system_includes or
                             search_paths_intermediate.framework_includes),
    }
    return dto

def _swift_to_dto(outputs):
    dto = {
        "m": file_path_to_dto(file_path(outputs.swiftmodule)),
    }

    if outputs.swift_generated_header:
        dto["h"] = file_path_to_dto(file_path(outputs.swift_generated_header))

    return dto

def _get_top_level_static_libraries(xcode_target):
    """Returns the static libraries needed to link the target.

    Args:
        xcode_target: A value returned from `xcode_targets.make`.

    Returns:
        A `list` of `File`s that need to be linked for the target.
    """
    linker_inputs = xcode_target.linker_inputs
    if not linker_inputs:
        fail("""\
Target '{}' requires `ObjcProvider` or `CcInfo`\
""".format(xcode_target.label))
    return linker_inputs.static_libraries

xcode_targets = struct(
    get_top_level_static_libraries = _get_top_level_static_libraries,
    make = _make_xcode_target,
    merge = _merge_xcode_target,
    to_dto = _xcode_target_to_dto,
)
