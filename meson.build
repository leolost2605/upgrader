project('io.github.leolost2605.updater', ['c', 'vala']
)

i18n = import('i18n')
gnome = import('gnome')

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))
pkgdatadir = join_paths(datadir, meson.project_name())

polkit_dep = dependency('polkit-gobject-1')
posix_dep = meson.get_compiler('vala').find_library('posix')

polkit_actiondir = polkit_dep.get_pkgconfig_variable('actiondir', define_variable: ['prefix', prefix])

subdir('data')
subdir('src')
subdir('po')

gnome.post_install(
     glib_compile_schemas: true
)
