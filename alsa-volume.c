#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <alsa/asoundlib.h>

typedef int (*set_volume_func)(snd_mixer_elem_t *, snd_mixer_selem_channel_id_t, long  );
typedef int (*set_switch_func)(snd_mixer_elem_t *, snd_mixer_selem_channel_id_t, int   );
typedef int (*get_volume_func)(snd_mixer_elem_t *, snd_mixer_selem_channel_id_t, long *);
typedef int (*get_switch_func)(snd_mixer_elem_t *, snd_mixer_selem_channel_id_t, int  *);
typedef int (*get_range_func)(snd_mixer_elem_t *, long *, long *);

void * get_func(char gs, char pc, char vsr) {
	if (gs == 'g') {
		if (pc == 'p') {
			if (vsr == 'v') return snd_mixer_selem_get_playback_volume;
			if (vsr == 's') return snd_mixer_selem_get_playback_switch;
			if (vsr == 'r') return snd_mixer_selem_get_playback_volume_range;
		}
		else if (pc == 'c') {
			if (vsr == 'v') return snd_mixer_selem_get_capture_volume;
			if (vsr == 's') return snd_mixer_selem_get_capture_switch;
			if (vsr == 'r') return snd_mixer_selem_get_capture_volume_range;
		}
	}
	else if (gs == 's') {
		if (pc == 'p') {
			if (vsr == 'v') return snd_mixer_selem_set_playback_volume;
			if (vsr == 's') return snd_mixer_selem_set_playback_switch;
		}
		else if (pc == 'c') {
			if (vsr == 'v') return snd_mixer_selem_set_capture_volume;
			if (vsr == 's') return snd_mixer_selem_set_capture_switch;
		}
	}
	fprintf(stderr, "unexpected function specification: %c%c%c\n", gs, pc, vsr);
	exit(101);
}

void die(int rv) {
	if (rv == 0) return;
	fputs(snd_strerror(rv), stderr);
	fputc('\n', stderr);
	exit(rv);
}

snd_mixer_t * get_handle() {
	snd_mixer_t * handle;
	die(snd_mixer_open          (&handle, 0         ));
	die(snd_mixer_attach        ( handle, "default" ));
	die(snd_mixer_selem_register( handle, NULL, NULL));
	die(snd_mixer_load          ( handle            ));
	return handle;
}

double get_volume(char pc, snd_mixer_elem_t * elem) {
	long min, max, left, right;

	get_range_func range = get_func('g', pc, 'r');
	die(range(elem, &min, &max));

	get_volume_func volume = get_func('g', pc, 'v');
	die(volume(elem, SND_MIXER_SCHN_FRONT_LEFT , &left ));
	die(volume(elem, SND_MIXER_SCHN_FRONT_RIGHT, &right));

	return (double)((left > right ? left : right) - min) / (double)(max - min);
}

void set_volume(char pc, snd_mixer_elem_t * elem, double value) {
	long min, max;

	get_range_func range = get_func('g', pc, 'r');
	die(range(elem, &min, &max));

	long val;
	if      (value < 0) val = min;
	else if (value > 1) val = max;
	else                val = min + (long)round((max - min) * value);
	set_volume_func volume = get_func('s', pc, 'v');
	die(volume(elem, SND_MIXER_SCHN_FRONT_LEFT , val));
	die(volume(elem, SND_MIXER_SCHN_FRONT_RIGHT, val));
}

int get_switch(char pc, snd_mixer_elem_t * elem) {
	int left, right;
	get_switch_func _switch = get_func('g', pc, 's');
	die(_switch(elem, SND_MIXER_SCHN_FRONT_LEFT , &left ));
	die(_switch(elem, SND_MIXER_SCHN_FRONT_RIGHT, &right));
	return left | right;
}

void set_switch(char pc, snd_mixer_elem_t * elem, int value) {
	set_switch_func _switch = get_func('s', pc, 's');
	die(_switch(elem, SND_MIXER_SCHN_FRONT_LEFT , value));
	die(_switch(elem, SND_MIXER_SCHN_FRONT_RIGHT, value));
}

const char * on_off(int s) {
	return s ? "on" : "off";
}

void usage_exit(char * name) {
	fprintf(stderr, "usage: %s [p[layback]|c[apture]|b[oth] [g[et]|m[ute]|u[nmute]|t[oggle]|[+|-]0-100]]\n", name);
	exit(1);
}

char get_device_spec(char * arg) {
	if (strcmp(arg, "playback") == 0 || strcmp(arg, "p") == 0)
		return 'p';
	if (strcmp(arg, "capture" ) == 0 || strcmp(arg, "c") == 0)
		return 'c';
	if (strcmp(arg, "both"    ) == 0 || strcmp(arg, "b") == 0)
		return 'b';
	return '\0';
}

int get_volume_spec(char * arg) {
	if (*arg == '\0') return 0xBADBAD;
	if (strcmp(arg,    "get") == 0 || strcmp(arg, "g") == 0) return 0x1000 + 'g';
	if (strcmp(arg,   "mute") == 0 || strcmp(arg, "m") == 0) return 0x1000 + 'm';
	if (strcmp(arg, "unmute") == 0 || strcmp(arg, "u") == 0) return 0x1000 + 'u';
	if (strcmp(arg, "toggle") == 0 || strcmp(arg, "t") == 0) return 0x1000 + 't';
	char * endptr;
	long vol = strtol(arg, &endptr, 10);
	if (*endptr != '\0') return 0xBADBAD;

	if (*arg == '+' || *arg == '-') return (int)vol;
	return 0x2000 + (int)vol;
}

void do_action(
	char device_spec,
	int volume_spec,
	snd_mixer_elem_t * playback,
	snd_mixer_elem_t * capture,
	char terminal
) {
	if (device_spec == 'b') {
		do_action('p', volume_spec, playback, capture, ' ');
		do_action('c', volume_spec, playback, capture, terminal);
		return;
	}

	char pc = device_spec;

	snd_mixer_elem_t * elem = pc == 'p' ? playback : capture;
	if (elem == NULL) {
		fprintf(
			stderr,
			"could not find a %s device",
			pc == 'p' ? "playback" : "capture"
		);
		exit(1);
	}
	if (volume_spec == 0x1000 + 'g')
		;
	else if (volume_spec == 0x1000 + 'm')
		set_switch(pc, elem, 0);
	else if (volume_spec == 0x1000 + 'u')
		set_switch(pc, elem, 1);
	else if (volume_spec == 0x1000 + 't')
		set_switch(pc, elem, !get_switch(pc, elem));
	else if (volume_spec >= 0x2000)
		set_volume(pc, elem, (volume_spec - 0x2000) * 0.01);
	else
		set_volume(pc, elem, get_volume(pc, elem) + volume_spec * 0.01);
	printf(
		"%lg %s%c",
		round(100 * get_volume(pc, elem)),
		on_off(get_switch(pc, elem)),
		terminal
	);
}

int main(int argc, char ** argv) {
	if (argc > 3) usage_exit(argv[0]);
	char device_spec = get_device_spec(argc > 1 ? argv[1] : "b");
	if (device_spec == '\0') usage_exit(argv[0]);
	int volume_spec = get_volume_spec(argc > 2 ? argv[2] : "g");
	if (volume_spec == 0xBADBAD) usage_exit(argv[0]);

	snd_mixer_t * handle = get_handle();

	snd_mixer_selem_id_t * sid;
	snd_mixer_selem_id_alloca(&sid);

	snd_mixer_elem_t * playback = NULL, * capture = NULL;

	for (
		snd_mixer_elem_t * elem = snd_mixer_first_elem(handle);
		elem != NULL;
		elem = snd_mixer_elem_next(elem)
	) {
		snd_mixer_selem_get_id(elem, sid);
		const char * name = snd_mixer_selem_id_get_name(sid);
		if (strcmp(name, "Master") == 0) {
			playback = elem;
		}
		else if (strcmp(name, "Capture") == 0) {
			capture = elem;
		}
	}
	do_action(device_spec, volume_spec, playback, capture, '\n');
	die(snd_mixer_close(handle));
}
