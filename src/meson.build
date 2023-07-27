updater_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
]

updater_deps = [
  dependency('gtk4'),
  dependency('packagekit-glib2'),
]

executable('updater', updater_sources,
  dependencies: updater_deps,
       install: true,
)
