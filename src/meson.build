updater_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
  'Apt' / 'DBus.vala'
]

updater_deps = [
  dependency('gtk4'),
  dependency('packagekit-glib2'),
  polkit_dep
]

executable('updater', updater_sources,
  dependencies: updater_deps,
       install: true,
)

subdir('Helper/UpgradeHelper')
subdir('Helper/RevertHelper')
