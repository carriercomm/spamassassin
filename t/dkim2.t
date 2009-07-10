#!/usr/bin/perl

use strict;
use warnings;
use re 'taint';
use lib '.'; use lib 't';

use SATest; sa_t_init("dkim2");
use Test;

use vars qw(%patterns %anti_patterns);

use constant num_tests => 122;

use constant TEST_ENABLED => conf_bool('run_net_tests');
use constant HAS_MODULES => eval { require Mail::DKIM; require Mail::DKIM::Verifier; };

use constant DO_RUN => TEST_ENABLED && HAS_MODULES;

BEGIN {
  if (-e 't/test_dir') {
    chdir 't';
  }

  if (-e 'test_dir') {
    unshift(@INC, '../blib/lib');
  }
  
  plan tests => (DO_RUN ? num_tests : 0);
};

exit unless (DO_RUN);

my $prefix = '.';
if (-e 'test_dir') {            # running from test directory, not ..
  $prefix = '..';
}

use IO::File;
use Mail::DKIM::Verifier;
use Mail::SpamAssassin;


# ---------------------------------------------------------------------------
my $spamassassin_obj;

sub process_sample_file($) {
  my($fn) = @_;  # file name
  my($mail_obj, $per_msg_status, $spam_report);
  $spamassassin_obj->timer_reset;
  my $fh = IO::File->new;
  $fh->open($fn,'<') or die "cannot open file $fn: $!";
  $mail_obj = $spamassassin_obj->parse($fh,0);
  if ($mail_obj) {
    local($1,$2,$3,$4,$5,$6);  # avoid Perl 5.8.x bug, $1 can get tainted
    $per_msg_status = $spamassassin_obj->check($mail_obj);
  }
  if ($per_msg_status) {
    $spam_report = $per_msg_status->get_tag('REPORT');
    $per_msg_status->finish;
  }
  if ($mail_obj) {
    $mail_obj->finish;
  }
  $fh->close or die "error closing file $fn: $!";
  $spam_report =~ s/\A(\s*\n)+//s;
# print "\t$spam_report\n";
  return $spam_report;
}

sub test_samples($$) {
  my($test_filenames, $patt_antipatt_list) = @_;
  for my $fn (sort { $a cmp $b } @$test_filenames) {
    my $el = @$patt_antipatt_list > 1 ? shift @$patt_antipatt_list
                                      : $patt_antipatt_list->[0];
    my($patt,$anti) = split(m{\s* / \s*}x, $el, 2);
    %patterns      = map { (" $_ ", $_) } split(' ',$patt);
    %anti_patterns = map { (" $_ ", $_) } split(' ',$anti);
    print "Testing sample $fn\n";
    my $spam_report = process_sample_file($fn);
    clear_pattern_counters();
    patterns_run_cb($spam_report);
    my $status = ok_all_patterns();
    printf("\nTest on file %s failed:\n%s\n", $fn,$spam_report)  if !$status;
  }
}

# ensure rules will fire, and disable some expensive ones
tstlocalrules("
  score DKIM_SIGNED          -0.1
  score DKIM_VALID           -0.1
  score DKIM_VALID_AU        -0.1
  score DKIM_ADSP_NXDOMAIN    0.1
  score DKIM_ADSP_DISCARD     0.1
  score DKIM_ADSP_ALL         0.1
  score DKIM_ADSP_CUSTOM_LOW  0.1
  score DKIM_ADSP_CUSTOM_MED  0.1
  score DKIM_ADSP_CUSTOM_HIGH 0.1
  score RAZOR2_CHECK 0
  score RAZOR2_CF_RANGE_51_100 0
  score RAZOR2_CF_RANGE_E4_51_100 0
  score RAZOR2_CF_RANGE_E8_51_100 0
");

my $dirname = "data/dkim";

$spamassassin_obj = Mail::SpamAssassin->new({
  rules_filename      => "$prefix/t/log/test_rules_copy",
  site_rules_filename => "$prefix/t/log/localrules.tmp",
  userprefs_filename  => "$prefix/masses/spamassassin/user_prefs",
  dont_copy_prefs   => 1,
  require_rules     => 1,
# debug             => 'dkim',
});
ok($spamassassin_obj);
$spamassassin_obj->compile_now;  # try to preloaded most modules

printf("Using Mail::DKIM version %s\n", Mail::DKIM::Verifier->VERSION);

# mail samples test-pass* should all pass DKIM validation
my($fn, @test_filenames, @patt_antipatt_list);
local *DIR;
opendir(DIR, $dirname) or die "Cannot open directory $dirname: $!";
while (defined($fn = readdir(DIR))) {
  next  if $fn eq '.' || $fn eq '..';
  next  if $fn !~ /^test-pass-\d*\.msg$/;
  push(@test_filenames, "$dirname/$fn");
}
closedir(DIR) or die "Error closing directory $dirname: $!";
@patt_antipatt_list = ( 'DKIM_SIGNED DKIM_VALID DKIM_VALID_AU /' );
test_samples(\@test_filenames, \@patt_antipatt_list);

# this mail sample is special, doesn't have any signature
@patt_antipatt_list = ( '/ DKIM_SIGNED DKIM_VALID' );
test_samples(["$dirname/test-fail-01.msg"], \@patt_antipatt_list);

# mail samples test-fail* should all fail DKIM validation
@test_filenames = ();
opendir(DIR, $dirname) or die "Cannot open directory $dirname: $!";
while (defined($fn = readdir(DIR))) {
  next  if $fn eq '.' || $fn eq '..';
  next  if $fn !~ /^test-fail-\d*\.msg$/;
  next  if $fn eq "test-fail-01.msg";  # no signature
  push(@test_filenames, "$dirname/$fn");
}
closedir(DIR) or die "Error closing directory $dirname: $!";
@patt_antipatt_list = ( 'DKIM_SIGNED / DKIM_VALID' );
test_samples(\@test_filenames, \@patt_antipatt_list);

# mail samples test-adsp* should all fail DKIM validation, testing ADSP
@test_filenames = ();
opendir(DIR, $dirname) or die "Cannot open directory $dirname: $!";
while (defined($fn = readdir(DIR))) {
  next  if $fn eq '.' || $fn eq '..';
  next  if $fn !~ /^test-adsp-\d*\.msg$/;
  push(@test_filenames, "$dirname/$fn");
}
closedir(DIR) or die "Error closing directory $dirname: $!";
@patt_antipatt_list = (
  ' / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_DISCARD DKIM_ADSP_ALL', # 11
  'DKIM_ADSP_NXDOMAIN / DKIM_VALID DKIM_ADSP_DISCARD  DKIM_ADSP_ALL', # 12
  'DKIM_ADSP_ALL  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_DISCARD', # 13
  'DKIM_ADSP_DISCARD  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_ALL', # 14
  'DKIM_ADSP_DISCARD  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_ALL', # 15
  ' / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_DISCARD DKIM_ADSP_ALL', # 16 foo
  ' / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_DISCARD DKIM_ADSP_ALL', # 17 unk
  'DKIM_ADSP_ALL  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_DISCARD', # 18 all
  'DKIM_ADSP_DISCARD  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_ALL', # 19 dis
  'DKIM_ADSP_DISCARD  / DKIM_VALID DKIM_ADSP_NXDOMAIN DKIM_ADSP_ALL', # 20 di2
  'DKIM_ADSP_DISCARD  / DKIM_VALID DKIM_ADSP_ALL',                    # 21 nxd
  '                   / DKIM_VALID DKIM_ADSP_DISCARD DKIM_ADSP_ALL',  # 22 xxx
);
test_samples(\@test_filenames, \@patt_antipatt_list);

END {
  $spamassassin_obj->finish  if $spamassassin_obj;
}
