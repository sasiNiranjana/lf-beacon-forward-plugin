PROJECT = lf_emqtt_online_status_submit
PROJECT_DESCRIPTION = Submitting console online status
PROJECT_VERSION = 2.1.0

BUILD_DEPS = emqttd cuttlefish
dep_emqttd = git https://github.com/emqtt/emqttd master
dep_cuttlefish = git https://github.com/emqtt/cuttlefish

NO_AUTOPATCH = cuttlefish

COVER = true

include erlang.mk

app:: rebar.config

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/lf_beacon_forward.config -i priv/lf_beacon_forward.schema -d data
