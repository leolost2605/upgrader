

[DBus (name = "org.debian.apt", timeout = 1800000)]
public interface Updater.Apt : GLib.Object {
    public abstract async string upgrade_system (bool safe_mode) throws GLib.Error;
}

[DBus (name = "org.debian.apt.transaction")]
public interface Updater.AptTransaction : GLib.Object {
    public abstract async void run () throws GLib.Error;

    public abstract async void simulate () throws GLib.Error;

    public abstract void cancel () throws GLib.Error;

    public signal void finished (string exit_state);

    public signal void property_changed (string property, Variant val);

    public signal void config_file_conflict (string old_config, string new_config);
}