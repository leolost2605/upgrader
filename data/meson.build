desktop_file = i18n.merge_file(
        input: 'io.github.leolost2605.updater.desktop.in',
       output: 'io.github.leolost2605.updater.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'io.github.leolost2605.updater.appdata.xml.in',
       output: 'io.github.leolost2605.updater.appdata.xml',
       po_dir: '../po',
      install: true,
  install_dir: join_paths(get_option('datadir'), 'appdata')
)

appstream_util = find_program('appstream-util', required: false)
if appstream_util.found()
  test('Validate appstream file', appstream_util, args: ['validate', appstream_file])
endif

install_data('io.github.leolost2605.updater.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0/schemas')
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file',
       compile_schemas,
       args: ['--strict', '--dry-run', meson.current_source_dir()])
endif

conf = configuration_data()
conf.set('PKGDATADIR', pkgdatadir)
conf.set('GETTEXT_PACKAGE', meson.project_name())

gettext_declaration = configure_file(
    configuration: conf,
    input: meson.project_name() + '.policy.in',
    output: meson.project_name() + '.policy.in'
)

i18n.merge_file(
    input: gettext_declaration,
    output: meson.project_name() + '.policy',
    po_dir: join_paths(meson.source_root(), 'po'),
    install: true,
    install_dir: polkit_actiondir
)

subdir('icons')
