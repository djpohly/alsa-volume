# alsa-volume

Simple ALSA volume control intended for use in scripts. It changes the playback/capture volume/mute state then responds with a description of the new state.

# why?

I haven't found anything that actually works for this and has output that's easy to parse. `amixer`'s output is hard to parse and its arguments are confusing. `pamixer` has arguments like `--get-default-sink` but no matching `--get-default-source` and it's necessary to specify a source explicitly. `ponymix` has very sensible default behavior but hasn't been updated in years and segfaults on half my machines.

# usage

The program works on its own, but the intended use is to be called from scripts, which is why the output format is so simple. For example, in AwesomeWM (Lua):

```
awful.spawn.easy_async(
    ('alsa-volume %s %s'):format(device, volume),
    function (stdout, stderr, exitreason, exitcode)
        if exitcode ~= 0 then return end
        local volume, on_off = split(stdout)
        -- update appropriate volume display
    end
)
```

Some concrete examples:

```
$ alsa-volume -h
usage: alsa-volume [p[layback]|c[apture]|b[oth] [g[et]|m[ute]|u[nmute]|t[oggle]|[+|-]0-100]]
$ alsa-volume both get  # full command names
34 on 0 on
$ alsa-volume b g  # single-letter versions
34 on 0 on
$ alsa-volume  # both get is the default behavior
34 on 0 on
$ alsa-volume playback mute  # mute even if muted
44 off
$ alsa-volume playback unmute  # unmute even if unmuted
44 on
$ alsa-volume playback toggle  # toggle muted state
44 off
$ alsa-volume playback 50  # set volume
50 on
$ alsa-volume playback +10  # increase volume
60 on
$ alsa-volume playback -5  # decrease volume
55 on
$ alsa-volume b m  # mute both playback and capture
50 off 0 off
```

# limitations

The names of the playback and capture devices are hardcoded as "Master" and "Capture" which might be limiting on systems that are purely running ALSA. I might change this if I find a way to change their names to something else and test.

The `snd_mixer_selem_set_*_volume()` functions don't seem to accept volumes greater than 100%, so it's not possible to boost the volume. `snd_mixer_selem_get_*_volume()` seems to report volumes in excess of 100% without issue, though.

# requirements

ALSA (libasound)

only tested with Pipewire
