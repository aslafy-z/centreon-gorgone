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

package gorgone::modules::core::cron::class;

use base qw(gorgone::class::module);

use strict;
use warnings;
use gorgone::standard::library;
use gorgone::standard::misc;
use ZMQ::LibZMQ4;
use ZMQ::Constants qw(:all);
use Schedule::Cron;

my %handlers = (TERM => {}, HUP => {});
my ($connector);

sub new {
    my ($class, %options) = @_;
    $connector  = {};
    $connector->{internal_socket} = undef;
    $connector->{logger} = $options{logger};
    $connector->{config} = $options{config};
    $connector->{config_core} = $options{config_core};
    $connector->{stop} = 0;
    
    bless $connector, $class;
    $connector->set_signal_handlers;
    return $connector;
}

sub set_signal_handlers {
    my $self = shift;

    $SIG{TERM} = \&class_handle_TERM;
    $handlers{TERM}->{$self} = sub { $self->handle_TERM() };
    $SIG{HUP} = \&class_handle_HUP;
    $handlers{HUP}->{$self} = sub { $self->handle_HUP() };
}

sub handle_HUP {
    my $self = shift;
    $self->{reload} = 0;
}

sub handle_TERM {
    my $self = shift;
    $self->{logger}->writeLogInfo("[cron] -class- $$ Receiving order to stop...");
    $self->{stop} = 1;
}

sub class_handle_TERM {
    foreach (keys %{$handlers{TERM}}) {
        &{$handlers{TERM}->{$_}}();
    }
}

sub class_handle_HUP {
    foreach (keys %{$handlers{HUP}}) {
        &{$handlers{HUP}->{$_}}();
    }
}

sub action_getcron {
    my ($self, %options) = @_;
    
    $options{token} = $self->generate_token() if (!defined($options{token}));

    my $data;
    my $id = $options{data}->{variables}[0];
    my $parameter = $options{data}->{variables}[1];
    if (defined($id) && $id ne '') {
        if (defined($parameter) && $parameter =~ /^status$/) {
            $self->{logger}->writeLogDebug("[cron] -class- Get logs results for definition '" . $id . "'");
            $self->send_internal_action(
                action => 'GETLOG',
                token => $options{token},
                data => {
                    token => $id,
                    ctime => $options{data}->{parameters}->{ctime},
                    etime => $options{data}->{parameters}->{etime},
                    limit => $options{data}->{parameters}->{limit},
                    code => $options{data}->{parameters}->{code}
                }
            );
            my $rev = zmq_poll($connector->{poll}, 5000);
            $data = $connector->{ack}->{data}->{data}->{result};
        } else {
            my $idx;
            eval {
                $idx = $self->{cron}->check_entry($id);
            };
            if ($@) {
                $self->{logger}->writeLogDebug("[cron] -class- Cron get failed to retrieve entry index");
                $self->send_log(
                    code => $self->ACTION_FINISH_KO,
                    token => $options{token},
                    data => { message => 'failed to retrieve entry index' }
                );
                return 1;
            }
            if (!defined($idx)) {
                $self->{logger}->writeLogDebug("[cron] -class- Cron get failed no entry found for id");
                $self->send_log(
                    code => $self->ACTION_FINISH_KO,
                    token => $options{token},
                    data => { message => 'no entry found for id' }
                );
                return 1;
            }

            eval {
                my $result = $self->{cron}->get_entry($idx);
                push @{$data}, { %{$result->{args}[1]->{definition}} } if (defined($result->{args}[1]->{definition}));
            };
            if ($@) {
                $self->{logger}->writeLogDebug("[cron] -class- Cron get failed");
                $self->send_log(
                    code => $self->ACTION_FINISH_KO,
                    token => $options{token},
                    data => { message => 'get failed:' . $@ }
                );
                return 1;
            }
        }
    } else {
        eval {
            my @results = $self->{cron}->list_entries();
            foreach my $cron (@results) {
                push @{$data}, { %{$cron->{args}[1]->{definition}} };
            }
        };
        if ($@) {
            $self->{logger}->writeLogDebug("[cron] -class- Cron get failed");
            $self->send_log(
                code => $self->ACTION_FINISH_KO,
                token => $options{token},
                data => { message => 'get failed:' . $@ }
            );
            return 1;
        }
    }

    $self->send_log(
        code => $self->ACTION_FINISH_OK,
        token => $options{token},
        data => $data
    );
    return 0;
}

sub action_addcron {
    my ($self, %options) = @_;
    
    $options{token} = $self->generate_token() if (!defined($options{token}));

    $self->{logger}->writeLogDebug("[cron] -class- Cron add start");

    foreach my $definition (@{$options{data}->{content}}) {
        if (!defined($definition->{timespec}) || $definition->{timespec} eq '' ||
            !defined($definition->{action}) || $definition->{action} eq '' ||
            !defined($definition->{id}) || $definition->{id} eq '') {
            $self->{logger}->writeLogDebug("[cron] -class- Cron add missing arguments");
            $self->send_log(
                code => $self->ACTION_FINISH_KO,
                token => $options{token},
                data => { message => 'missing arguments' }
            );
            return 1;
        }
    }
    
    eval {
        foreach my $definition (@{$options{data}->{content}}) {
            my $idx = $self->{cron}->check_entry($definition->{id});
            if (defined($idx)) {
                $self->send_log(
                    code => $self->ACTION_FINISH_KO,
                    token => $options{token},
                    data => { message => "id '" . $definition->{id} . "' already exists" }
                );
                next;
            }
            $self->{logger}->writeLogInfo("[cron] -class- Adding cron definition '" . $definition->{id} . "'");
            $self->{cron}->add_entry(
                $definition->{timespec},
                $definition->{id},
                {
                    socket => $connector->{internal_socket},
                    logger => $self->{logger},
                    definition => $definition
                }
            );
        }
    };
    if ($@) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron add failed");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'add failed:' . $@ }
        );
        return 1;
    }

    $self->{logger}->writeLogDebug("[cron] -class- Cron add finish");
    $self->send_log(
        code => $self->ACTION_FINISH_OK,
        token => $options{token},
        data => { message => 'add succeed' }
    );
    return 0;
}

sub action_updatecron {
    my ($self, %options) = @_;
    
    $options{token} = $self->generate_token() if (!defined($options{token}));

    $self->{logger}->writeLogDebug("[cron] -class- Cron update start");
    
    my $id = $options{data}->{variables}[0];
    if (!defined($id)) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron update missing id");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'missing id' }
        );
        return 1;
    }

    my $idx;
    eval {
        $idx = $self->{cron}->check_entry($id);
    };
    if ($@) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron update failed to retrieve entry index");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'failed to retrieve entry index' }
        );
        return 1;
    }
    if (!defined($idx)) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron update failed no entry found for id");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'no entry found for id' }
        );
        return 1;
    }
    
    my $definition = $options{data}->{content};
    if ((!defined($definition->{timespec}) || $definition->{timespec} eq '') &&
        (!defined($definition->{command_line}) || $definition->{command_line} eq '')) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron update missing arguments");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'missing arguments' }
        );
        return 1;
    }
    
    eval {
        my $entry = $self->{cron}->get_entry($idx);
        $entry->{time} = $definition->{timespec};
        $entry->{args}[1]->{definition}->{timespec} = $definition->{timespec}
            if (defined($definition->{timespec}));
        $entry->{args}[1]->{definition}->{command_line} = $definition->{command_line}
            if (defined($definition->{command_line}));
        $self->{cron}->update_entry($idx, $entry);
    };
    if ($@) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron update failed");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'update failed:' . $@ }
        );
        return 1;
    }

    $self->{logger}->writeLogDebug("[cron] -class- Cron update succeed");
    $self->send_log(
        code => $self->ACTION_FINISH_OK,
        token => $options{token},
        data => { message => 'update succeed' }
    );
    return 0;
}

sub action_deletecron {
    my ($self, %options) = @_;
    
    $options{token} = $self->generate_token() if (!defined($options{token}));

    $self->{logger}->writeLogDebug("[cron] -class- Cron delete start");
    
    my $id = $options{data}->{variables}[0];
    if (!defined($id) || $id eq '') {
        $self->{logger}->writeLogDebug("[cron] -class- Cron delete missing id");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'missing id' }
        );
        return 1;
    }

    my $idx;
    eval {
        $idx = $self->{cron}->check_entry($id);
    };
    if ($@) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron delete failed to retrieve entry index");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'failed to retrieve entry index' }
        );
        return 1;
    }
    if (!defined($idx)) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron delete failed no entry found for id");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'no entry found for id' }
        );
        return 1;
    }
    
    eval {
        $self->{cron}->delete_entry($idx);
    };
    if ($@) {
        $self->{logger}->writeLogDebug("[cron] -class- Cron delete failed");
        $self->send_log(
            code => $self->ACTION_FINISH_KO,
            token => $options{token},
            data => { message => 'delete failed:' . $@ }
        );
        return 1;
    }

    $self->{logger}->writeLogDebug("[cron] -class- Cron delete finish");
    $self->send_log(
        code => $self->ACTION_FINISH_OK,
        token => $options{token},
        data => { message => 'delete succeed' }
    );
    return 0;
}

sub event {
    while (1) {
        my $message = gorgone::standard::library::zmq_dealer_read_message(socket => $connector->{internal_socket});

        $connector->{logger}->writeLogDebug("[cron] -class- Event: $message");
        if ($message =~ /^\[ACK\]\s+\[(.*?)\]\s+(.*)$/m) {
            my $token = $1;
            my $data = JSON::XS->new->utf8->decode($2);
            $connector->{ack} = {
                token => $token,
                data => $data,
            };
        } else {
            $message =~ /^\[(.*?)\]\s+\[(.*?)\]\s+\[.*?\]\s+(.*)$/m;
            if ((my $method = $connector->can('action_' . lc($1)))) {
                $message =~ /^\[(.*?)\]\s+\[(.*?)\]\s+\[.*?\]\s+(.*)$/m;
                my ($action, $token) = ($1, $2);
                my $data = JSON::XS->new->utf8->decode($3);
                $method->($connector, token => $token, data => $data);
            }
        }
        
        last unless (gorgone::standard::library::zmq_still_read(socket => $connector->{internal_socket}));
    }
}

sub cron_sleep {
    my $rev = zmq_poll($connector->{poll}, 1000);
    if ($rev == 0 && $connector->{stop} == 1) {
        $connector->{logger}->writeLogInfo("[cron] -class- $$ has quit");
        zmq_close($connector->{internal_socket});
        exit(0);
    }
}

sub dispatcher {
    my ($id, $options) = @_;

    $options->{logger}->writeLogInfo("[cron] -class- Launching job '" . $id . "'");

    my $token = (defined($options->{definition}->{keep_token})) ? $options->{definition}->{id} : undef;

    gorgone::standard::library::zmq_send_message(
        socket => $options->{socket},
        token => $token,
        action => $options->{definition}->{action},
        target => $options->{definition}->{target},
        data => {
            content => { %{$options->{definition}->{parameters}} }
        },
        json_encode => 1
    );
 
    my $poll = [
        {
            socket  => $options->{socket},
            events  => ZMQ_POLLIN,
            callback => \&event,
        }
    ];

    my $rev = zmq_poll($poll, 5000);
}

sub run {
    my ($self, %options) = @_;

    # Connect internal
    $connector->{internal_socket} = gorgone::standard::library::connect_com(
        zmq_type => 'ZMQ_DEALER',
        name => 'gorgonecron',
        logger => $self->{logger},
        type => $self->{config_core}->{internal_com_type},
        path => $self->{config_core}->{internal_com_path}
    );
    gorgone::standard::library::zmq_send_message(
        socket => $connector->{internal_socket},
        action => 'CRONREADY', data => { },
        json_encode => 1
    );
    $connector->{poll} = [
        {
            socket  => $connector->{internal_socket},
            events  => ZMQ_POLLIN,
            callback => \&event,
        }
    ];

    push @{$self->{config}->{cron}}, {
        id => "default",
        timespec => "0 0 * * *",
        action => "COMMAND",
        parameters => {
            command => "date >> /tmp/date.log",
            timeout => 2,
        }
    };

    $self->{cron} = new Schedule::Cron(\&dispatcher, nostatus => 1, nofork => 1, catch => 1);

    foreach my $definition (@{$self->{config}->{cron}}) {
        $self->{cron}->add_entry(
            $definition->{timespec},
            $definition->{id},
            {
                socket => $connector->{internal_socket},
                logger => $self->{logger},
                definition => $definition
            }
        );
    }
        
    $self->{cron}->run(sleep => \&cron_sleep);

    zmq_close($connector->{internal_socket});
    exit(0);
}

1;
