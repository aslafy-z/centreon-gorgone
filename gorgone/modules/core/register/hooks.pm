# 
# Copyright 2019 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package gorgone::modules::core::register::hooks;

use warnings;
use strict;
use JSON::XS;
use gorgone::class::core;
use gorgone::modules::core::register::class;

use constant NAMESPACE => 'core';
use constant NAME => 'register';
use constant EVENTS => [
    { event => 'REGISTERREADY' },
];

my $config_core;
my $config;
my ($config_db_centreon);
my $register = {};
my $stop = 0;

sub register {
    my (%options) = @_;

    my $loaded = 1;
    $config = $options{config};
    $config_core = $options{config_core};
    if (!defined($config->{config_file}) || $config->{config_file} =~ /^\s*$/) {
        $options{logger}->writeLogError('[register] -hooks- config_file option mandatory');
        $loaded = 0;
    }
    return ($loaded, NAMESPACE, NAME, EVENTS);
}

sub init {
    my (%options) = @_;

    create_child(logger => $options{logger});
}

sub routing {
    my (%options) = @_;

    my $data;
    eval {
        $data = JSON::XS->new->utf8->decode($options{data});
    };
    if ($@) {
        $options{logger}->writeLogError("[register] -hooks- Cannot decode json data: $@");
        gorgone::standard::library::add_history(
            dbh => $options{dbh},
            code => 10, token => $options{token},
            data => { message => 'gorgoneregister: cannot decode json' },
            json_encode => 1
        );
        return undef;
    }
    
    if ($options{action} eq 'REGISTERREADY') {
        $register->{ready} = 1;
        return undef;
    }
    
    if (gorgone::class::core::waiting_ready(ready => \$register->{ready}) == 0) {
        gorgone::standard::library::add_history(
            dbh => $options{dbh},
            code => 10, token => $options{token},
            data => { message => 'gorgoneregister: still no ready' },
            json_encode => 1
        );
        return undef;
    }
    
    gorgone::standard::library::zmq_send_message(
        socket => $options{socket},
        identity => 'gorgoneregister',
        action => $options{action},
        data => $options{data},
        token => $options{token},
    );
}

sub gently {
    my (%options) = @_;

    $stop = 1;
    $options{logger}->writeLogInfo("[register] -hooks- Send TERM signal");
    if ($register->{running} == 1) {
        CORE::kill('TERM', $register->{pid});
    }
}

sub kill {
    my (%options) = @_;

    if ($register->{running} == 1) {
        $options{logger}->writeLogInfo("[register] -hooks- Send KILL signal for pool");
        CORE::kill('KILL', $register->{pid});
    }
}

sub kill_internal {
    my (%options) = @_;

}

sub check {
    my (%options) = @_;

    my $count = 0;
    foreach my $pid (keys %{$options{dead_childs}}) {
        # Not me
        next if ($register->{pid} != $pid);
        
        $register = {};
        delete $options{dead_childs}->{$pid};
        if ($stop == 0) {
            create_child(logger => $options{logger});
        }
    }
    
    $count++ if (defined($register->{running}) && $register->{running} == 1);
    
    return $count;
}

# Specific functions
sub create_child {
    my (%options) = @_;

    $options{logger}->writeLogInfo("[register] -hooks- Create module 'register' process");
    my $child_pid = fork();
    if ($child_pid == 0) {
        $0 = 'gorgone-register';
        my $module = gorgone::modules::core::register::class->new(
            logger => $options{logger},
            config_core => $config_core,
            config => $config,
        );
        $module->run();
        exit(0);
    }
    $options{logger}->writeLogInfo("[register] -hooks- PID $child_pid (gorgone-register)");
    $register = { pid => $child_pid, ready => 0, running => 1 };
}

1;
