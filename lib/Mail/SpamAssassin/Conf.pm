#

package Mail::SpamAssassin::Conf;

use Carp;
use strict;

use Mail::Audit;

use vars	qw{
  	@ISA
};

@ISA = qw();

###########################################################################

sub new {
  my $class = shift;
  $class = ref($class) || $class;

  my $self = {
    'main' => shift,
  }; bless ($self, $class);

  $self->{body_tests} = { };
  $self->{head_tests} = { };
  $self->{head_evals} = { };
  $self->{body_evals} = { };
  $self->{full_evals} = { };
  $self->{descriptions} = { };

  $self->{scores} = { };
  $self->{required_hits} = 5;
  $self->{razor_host} = 'razor.vipul.net';
  $self->{razor_port} = 2702;
  $self->{report_template} = '';

  $self;
}

###########################################################################

sub parse_rules {
  my ($self, $rules) = @_;
  local ($_);

  my $counter = 'aaaaa';

  foreach $_ (split (/\n/, $rules)) {
    s/\r//g; s/(?<!\\)\#.*$//; s/^\s+//; s/\s+$//; /^$/ and next;

    if (/^header\s+(\S+)\s+eval:(.*)$/) {
      my $name = $1; my $sub = $2;
      $self->{head_evals}->{$name} = $sub;
      $self->{scores}->{$name} ||= 1;
      next;
    }

    if (/^header\s+(\S+)\s+(.*)$/) {
      my $name = $1; my $tst = $2;
      $self->{head_tests}->{$name} = $tst;
      $self->{scores}->{$name} ||= 1;
      next;
    }

    if (/^describe\s+(\S+)\s+(.*)$/) {
      $self->{descriptions}->{$1} = $2;
      next;
    }

    if (/^body\s+(\S+)\s+eval:(.*)$/) {
      my $name = $1; my $sub = $2;
      $self->{body_evals}->{$name} = $sub;
      $self->{scores}->{$name} ||= 1;
      next;
    }

    if (/^body\s+(\S+)\s+(.*)$/) {
      my $name = $1; my $tst = $2;
      if ($name eq '.') { $name = ($counter++); }
      $self->{body_tests}->{$name} = $tst;
      $self->{scores}->{$name} ||= 1;
      next;
    }

    if (/^full\s+(\S+)\s+eval:(.*)$/) {
      my $name = $1; my $sub = $2;
      $self->{full_evals}->{$name} = $sub;
      $self->{scores}->{$name} ||= 1;
      next;
    }

    if (/^required_hits\s+(\d+)$/) {
      $self->{required_hits} = $1+0;
      next;
    }

    if (/^razor_server\s+(\S+)$/) {
      $self->{razor_host} = $1;

      if ($self->{razor_host} =~ s/:(\d+)$//) {
	$self->{razor_port} = $1+0;
	if ($self->{razor_port} == 0) { goto failed_line; }
      } else {
	$self->{razor_port} = 2702;		# default port
      }
      next;
    }

    if (/^score\s+(\S+)\s+(\-*\d+)$/) {
      $self->{scores}->{$1} = $2+0;
      next;
    }

    if (/^report\s*(.*)$/) {
      $self->{report_template} .= $1."\n";
      next;
    }

failed_line:
    warn "Failed to parse line in SpamAssassin configuration, skipping: $_\n";
  }
}

###########################################################################

1;
