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

package gorgone::class::http::backend::curl;

use strict;
use warnings;
use URI;
use gorgone::standard::misc;

sub new {
    my ($class, %options) = @_;
    my $self  = {};
    bless $self, $class;
    
    $self->{logger} = $options{logger};
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;

    if (gorgone::standard::misc::mymodule_load(
        logger => $self->{logger}, module => 'Net::Curl::Easy',
        error_msg => "Cannot load module 'Net::Curl::Easy'."
        ) == 1) {
        return 1;
    }
    if (gorgone::standard::misc::mymodule_load(
        logger => $self->{logger}, module => 'gorgone::class::http::backend::curlconstants',
        error_msg => "Cannot load module 'gorgone::class::http::backend::curlconstants'."
        ) == 1) {
        return 1;
    }
    $self->{constant_cb} = \&gorgone::class::http::backend::curlconstants::get_constant_value;

    if (!defined($options{request}->{curl_opt})) {
        $options{request}->{curl_opt} = [];
    }
}

my $http_code_explained = {
    100 => 'Continue',
    101 => 'Switching Protocols',
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    306 => '(Unused)',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Long',
    415 => 'Unsupported Media Type',
    416 => 'Requested Range Not Satisfiable',
    417 => 'Expectation Failed',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
};

sub cb_debug {
    my ($easy, $type, $data, $uservar) = @_;

    my $msg = '';
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_TEXT')) {
        $msg = sprintf("== Info: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_HEADER_OUT')) {
        $msg = sprintf("=> Send header: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_DATA_OUT')) {
        $msg = sprintf("=> Send data: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_SSL_DATA_OUT')) {
        $msg = sprintf("=> Send SSL data: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_HEADER_IN')) {
        $msg = sprintf("=> Recv header: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_DATA_IN')) {
        $msg = sprintf("=> Recv data: %s", $data);
    }
    if ($type == $uservar->{constant_cb}->(name => 'CURLINFO_SSL_DATA_IN')) {
        $msg = sprintf("=> Recv SSL data: %s", $data);
    }
    
    $uservar->{logger}->writeLogDebug($msg);
    return 0;
}

sub curl_setopt {
    my ($self, %options) = @_;
    
    eval {
        $self->{curl_easy}->setopt($options{option}, $options{parameter});
    };
    if ($@) {
        $self->{logger}->writeLogError("curl setopt error: '" . $@ . "'.");
    }
}

sub set_method {
    my ($self, %options) = @_;

    if ($options{request}->{method} eq 'GET') {
        return ;
    }
    
    if ($options{content_type_forced} == 1) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_POSTFIELDS'), parameter => $options{request}->{query_form_post})
            if (defined($options{request}->{query_form_post}) && $options{request}->{query_form_post} ne '');
    } elsif (defined($options{request}->{post_params})) {
        my $uri_post = URI->new();
        $uri_post->query_form($options{request}->{post_params});
        push @{$options{headers}}, 'Content-Type: application/x-www-form-urlencoded';
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_POSTFIELDS'), parameter => $uri_post->query);
    }
    
    if ($options{request}->{method} eq 'POST') {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_POST'), parameter => 1);
    }
    if ($options{request}->{method} eq 'PUT') {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_CUSTOMREQUEST'), parameter => $options{request}->{method});
    }
    if ($options{request}->{method} eq 'DELETE') {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_CUSTOMREQUEST'), parameter => $options{request}->{method});
    }
}

sub set_auth {
    my ($self, %options) = @_;

    if (defined($options{request}->{credentials})) {
        if (defined($options{request}->{basic})) {
            $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_HTTPAUTH'), parameter => $self->{constant_cb}->(name => 'CURLAUTH_BASIC'));
        } elsif (defined($options{request}->{ntlmv2})) {
            $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_HTTPAUTH'), parameter => $self->{constant_cb}->(name => 'CURLAUTH_NTLM'));
        } else {
            $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_HTTPAUTH'), parameter => $self->{constant_cb}->(name => 'CURLAUTH_ANY'));
        }
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_USERPWD'), parameter => $options{request}->{username}  . ':' . $options{request}->{password});
    }

    if (defined($options{request}->{cert_file}) &&  $options{request}->{cert_file} ne '') {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_SSLCERT'), parameter => $options{request}->{cert_file});
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_SSLKEY'), parameter => $options{request}->{key_file});
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_KEYPASSWD'), parameter => $options{request}->{cert_pwd});
    }
    
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_SSLCERTTYPE'), parameter => "PEM");
    if (defined($options{request}->{cert_pkcs12})) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_SSLCERTTYPE'), parameter => "P12");
    }
}

sub set_proxy {
    my ($self, %options) = @_;

    if (defined($options{request}->{proxyurl}) && $options{request}->{proxyurl} ne '') {
        if ($options{request}->{proxyurl} =~ /^(?:http|https):\/\/(.*?):(.*?)@/) {
            $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_PROXYUSERNAME'), parameter => $1);
            $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_PROXYPASSWORD'), parameter => $2);
            $options{request}->{proxyurl} =~ s/\/\/$1:$2@//;
        }
        
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_PROXY'), parameter => $options{request}->{proxyurl});
    }
    
    if (defined($options{request}->{proxypac}) && $options{request}->{proxypac} ne '') {
        $self->{logger}->writeLogError('Unsupported proxypac option');
    }
}

sub set_extra_curl_opt {
    my ($self, %options) = @_;

    my $fields = { key => '', value => '' };
    foreach (@{$options{request}->{curl_opt}}) {
        ($fields->{key}, $fields->{value}) = split /=>/;
        foreach my $label ('key', 'value') {
            $fields->{$label} = gorgone::standard::misc::trim($fields->{$label});
            if ($fields->{$label} =~ /^CURLOPT|CURL/) {
                $fields->{$label} = $self->{constant_cb}->(name => $fields->{$label});
            }
        }

        $self->curl_setopt(option => $fields->{key}, parameter => $fields->{value});
    }
}

sub cb_get_header {
    my ($easy, $header, $uservar) = @_;

    $header =~ s/[\r\n]//g;
    if ($header =~ /^[\r\n]*$/) {
        $uservar->{nheaders}++;
    } else {
        $uservar->{response_headers}->[$uservar->{nheaders}] = {}
            if (!defined($uservar->{response_headers}->[$uservar->{nheaders}]));
        if ($header =~  /^(\S(?:.*?))\s*:\s*(.*)/) {
            my $header_name = lc($1);
            $uservar->{response_headers}->[$uservar->{nheaders}]->{$header_name} = []
                if (!defined($uservar->{response_headers}->[$uservar->{nheaders}]->{$header_name}));
            push @{$uservar->{response_headers}->[$uservar->{nheaders}]->{$header_name}}, $2;
        } else {
           $uservar->{response_headers}->[$uservar->{nheaders}]->{response_line} = $header; 
        }
    }
    
    return length($_[1]);
}

sub request {
    my ($self, %options) = @_;

    $self->{curl_easy} = Net::Curl::Easy->new();
    
    if ($self->{logger}->is_debug()) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_DEBUGFUNCTION'), parameter => \&cb_debug);
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_DEBUGDATA'), parameter => $self);
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_VERBOSE'), parameter => 1);
    }

    if (defined($options{request}->{timeout})) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_TIMEOUT'), parameter => $options{request}->{timeout});
    }
    if (defined($options{request}->{cookies_file})) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_COOKIEFILE'), parameter => $options{request}->{cookies_file});
    }
    
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_FOLLOWLOCATION'), parameter => 1);
    if (defined($options{request}->{no_follow})) {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_FOLLOWLOCATION'), parameter => 0);
    }

    my $url;
    if (defined($options{request}->{full_url})) {
        $url = $options{request}->{full_url};
    } elsif (defined($options{request}->{port}) && $options{request}->{port} =~ /^[0-9]+$/) {
        $url = $options{request}->{proto}. "://" . $options{request}->{hostname} . ':' . $options{request}->{port} . $options{request}->{url_path};
    } else {
        $url = $options{request}->{proto}. "://" . $options{request}->{hostname} . $options{request}->{url_path};
    }

    if (defined($options{request}->{http_peer_addr}) && $options{request}->{http_peer_addr} ne '') {
        $url =~ /^(?:http|https):\/\/(.*?)(\/|\:|$)/;
        $self->{curl_easy}->pushopt($self->{constant_cb}->(name => 'CURLOPT_RESOLVE'),
               [$1 . ':' . $options{request}->{port_force} . ':' . $options{request}->{http_peer_addr}]);
    }    

    my $uri = URI->new($url);
    if (defined($options{request}->{get_params})) {
        $uri->query_form($options{request}->{get_params});
    }
    
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_URL'), parameter => $uri);
    
    my $headers = [];
    my $content_type_forced = 0;
    foreach my $key (keys %{$options{request}->{headers}}) {
        push @$headers, $key . ':' . $options{request}->{headers}->{$key};
        if ($key =~ /content-type/i) {
            $content_type_forced = 1;
        }
    }
    
    $self->set_method(%options, content_type_forced => $content_type_forced, headers => $headers);
    
    if (scalar(@$headers) > 0) {
        $self->{curl_easy}->pushopt($self->{constant_cb}->(name => 'CURLOPT_HTTPHEADER'), $headers);
    }
    
    if (defined($options{request}->{cacert_file}) && $options{request}->{cacert_file} ne '') {
        $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_CAINFO'), parameter => $options{request}->{cacert_file});
    }
    
    $self->set_auth(%options);
    $self->set_proxy(%options);
    $self->set_extra_curl_opt(%options);

    $self->{response_body} = '';
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_FILE'), parameter => \$self->{response_body});
    $self->{nheaders} = 0;
    $self->{response_headers} = [{}];
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_HEADERDATA'), parameter => $self);
    $self->curl_setopt(option => $self->{constant_cb}->(name => 'CURLOPT_HEADERFUNCTION'), parameter => \&cb_get_header);
        
    eval {
        $self->{curl_easy}->perform();
    };
    if ($@) {
        $self->{logger}->writeLogError('curl perform error : ' . $@);
        return 1;
    }
    
    $self->{response_code} = $self->{curl_easy}->getinfo($self->{constant_cb}->(name => 'CURLINFO_RESPONSE_CODE'));

    return (0, $self->{response_body});
}

sub get_headers {
    my ($self, %options) = @_;
    
    my $headers = '';
    foreach (keys %{$self->{response_headers}->[$options{nheader}]}) {
        next if (/response_line/);
        foreach my $value (@{$self->{response_headers}->[$options{nheader}]->{$_}}) {
            $headers .= "$_: " . $value . "\n";
        }
    }
    
    return $headers;
}

sub get_first_header {
    my ($self, %options) = @_;
    
    if (!defined($options{name})) {
        return $self->get_headers(nheader => 0);
    }
    
    return undef
        if (!defined($self->{response_headers}->[0]->{ lc($options{name}) }));
    return wantarray ? @{$self->{response_headers}->[0]->{ lc($options{name}) }} : $self->{response_headers}->[0]->{ lc($options{name}) }->[0];
}

sub get_header {
    my ($self, %options) = @_;

    if (!defined($options{name})) {
        return $self->get_headers(nheader => -1);
    }

    return undef
        if (!defined($self->{response_headers}->[-1]->{ lc($options{name}) }));
    return wantarray ? @{$self->{response_headers}->[-1]->{ lc($options{name}) }} : $self->{response_headers}->[-1]->{ lc($options{name}) }->[0];
}

sub get_code {
    my ($self, %options) = @_;

    return $self->{response_code};
}

sub get_message {
    my ($self, %options) = @_;
    
    return $http_code_explained->{$self->{response_code}};
}

1;

__END__

=head1 NAME

HTTP Curl backend layer.

=head1 SYNOPSIS

HTTP Curl backend layer.

=head1 BACKEND CURL OPTIONS

=over 8

=item B<--curl-opt>

Set CURL Options (--curl-opt="CURLOPT_SSL_VERIFYPEER => 0" --curl-opt="CURLOPT_SSLVERSION => CURL_SSLVERSION_TLSv1_1" ).

=back

=head1 DESCRIPTION

B<http>.

=cut
