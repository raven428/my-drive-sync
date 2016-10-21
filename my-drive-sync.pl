#!/usr/bin/env perl
#
# $Id: my-drive-sync.pl,v 1.1.1.1 2016/10/21 13:28:58 raven Exp $
#
use strict;
use warnings;

our $WHOAMI = 'my-drive-sync';
our $VERSION = '$Revision: 1.1.1.1 $'; $VERSION =~ s/^\$Revision\:\s([\d\.]+)\s\$$/$1/i;

{
 package Net::Google::Drive::Simple::Mirror;
 use strict;
 use warnings;
 use Net::Google::Drive::Simple;
 use DateTime::Format::RFC3339;
 use DateTime;
 use File::Path;
 use Carp;
 our $VERSION = '0.53-raven';
 sub new {
  my($class, %options) = @_;
  croak("Local folder '$options{local_root}' not found")
   unless(-d($options{local_root}));
  $options{local_root} .= '/'
   unless($options{local_root} =~ m{/$});
  my $gd = Net::Google::Drive::Simple->new();
  $options{remote_root} = '/'.$options{remote_root}
   unless($options{remote_root} =~ m{^/});
  my(undef, $remote_root_ID) = $gd->children($options{remote_root});
  my $self = {
   remote_root_ID		=> $remote_root_ID,
   export_format		=> ['opendocument', 'html'],
   download_condition	=> \&_should_download,
   force			=> undef,
   net_google_drive_simple => $gd,
   excludes			=> undef,
   %options,
  };
  bless $self, $class;
 };
 sub mirror{
  my $self = shift();
  _process_folder(
   $self,
   $self->{remote_root_ID},
   $self->{local_root}
  );
 };
 sub _process_folder {
  my ($self, $folder_id, $path) = @_;
  my $gd = $self->{net_google_drive_simple};
  my $children = $gd->children_by_folder_id($folder_id);
  CHILDREN: for my $child (@$children) {
   my $file_name = $child->title();
   $file_name =~ s{/}{_};
   my $local_file = $path.$file_name;
   utf8::decode($local_file);
   my $download_target;
   if ($child->can('exportLinks')) {
    next() unless($self->{download_condition}->($self, $child, $local_file));
    print("$local_file ..exporting\n");
    my $type;
    FOUND: foreach my $preferred_type(@{$self->{export_format}}) {
     foreach my $t (keys %{$child->exportLinks()}) {
      $type = $t;
      last(FOUND) if($t =~ /$preferred_type/);
     };
    };
    $download_target = $child->exportLinks()->{$type};
   };
   if(
    $child->can('downloadUrl')
    and not defined($download_target)
   ) {
    next() unless($self->{download_condition}->($self, $child, $local_file));
    print("$local_file ..downloading\n");
    $download_target = $child;
   };
   if(defined($download_target)) {
    my $parent_dir = just_path_name($local_file);
    File::Path::make_path(
     $parent_dir, {
      'error'    => \my $errors
     },
    );
    if(@$errors) {
     my @errors = ();
     for my $diag(@$errors) {
      my($file, $message) = %$diag;
      if ($file eq '') {
       push(@errors, lc("gen: [$message]"));
      } else {
       push(@errors, lc("[$file]: [$message]"));
      };
     };
     warn(sprintf(
      "unable mkpath [%s], cause [%s] error\n",
      $parent_dir,
      join(', ', @errors),
     ));
    };
    $gd->download($download_target, $local_file);
    next();
   };
   if(defined($self->{excludes})) {
    foreach my $e(@{$self->{excludes}}) {
     my $p =  $self->{local_root};
     $local_file =~ s/^$p//;
     if($local_file =~ /$e/i) {
      print("skipping directory [$local_file], because of [$e] regexp\n");
      next(CHILDREN);
     };
    };
   };
   _process_folder($self, $child->id(), $path.$file_name.'/');
  };
 };
 sub _should_download{
  my ($self, $remote_file, $local_file) = @_;
  return 1 if $self->{force};
  my $date_time_parser = DateTime::Format::RFC3339->new();
  my $local_epoch =  (stat($local_file))[9];
  my $remote_epoch = $date_time_parser->parse_datetime(
   $remote_file->modifiedDate()
  )->epoch();
  if (
   -f($local_file)
   and ($remote_epoch < $local_epoch)
  ) {
   return 0;
  } else {
   return 1;
  };
 };
 sub just_path_name($) {
  my @folders = split(/\//, shift());
  pop(@folders);
  return(join('/', @folders));
 };
 1;
};

{
 package raven::my_drive_sync;
 use strict;
 use warnings;
 use Data::Dumper;
 use Getopt::Long;
 use File::Find;
 use utf8;

 # methods:
 sub CREATE {
  my $class = shift();
  $class = ref($class) || $class;
  my $options = shift();
  my $self = {
   'debug'		=> $options->{'debug'},
   %$options,
  };
  bless($self, $class);
  $self->{'WHOAMI'} = $WHOAMI;
  $self->{'VERSION'} = $VERSION;
  $Data::Dumper::Indent = 1;
  umask(0077);
  return($self);
 };
 sub run {
  my $self = shift();
  print("$WHOAMI v$VERSION by raVen\n");
  my $oldwarn = $SIG{__WARN__};
  $SIG{__WARN__} = sub {
   my $message = shift();
   if ($message =~ /^unknown\soption\:\s(.+?)$/i) {
    warn("! warning: unknown [--$1] option\n");
   } elsif ($message =~ /^option\s(.+?)\srequires\san\sargument$/i) {
    warn("! warning: option [--$1] requires an argument\n");
   };
  };
  my($dstdir, $excludes, $delete);
  my $optres = GetOptions(
   'dstdir=s@'	=> \$dstdir,
   'exclude=s@'	=> \$excludes,
   'delete'		=> \$delete,
  );
  $SIG{__WARN__} = $oldwarn;
  error_and_usage('wrong command line') unless($optres);
  error_and_usage('no destination directory assigned, use [--dstdir]') unless($dstdir);
  $self->{'c'}->{'dstdir'} = join('', @$dstdir);
  if(defined($excludes)) {
   $self->{'c'}->{'excludes'} = [];
   foreach my $e(@$excludes) {
    push(@{$self->{'c'}->{'excludes'}}, "^$e" . '$');
   };
  };
  my($dirs, $files) = ({}, {});
  binmode(STDOUT, ':encoding(UTF-8)');
  my $google_docs = Net::Google::Drive::Simple::Mirror->new(
   remote_root	=> '/',
   local_root	=> $self->{'c'}->{'dstdir'},
   export_format	=> ['officedocument', 'html'],
   excludes		=> $self->{'c'}->{'excludes'},
   download_condition => sub {
    my ($self, $remote_file, $local_file) = @_;
    if(defined($delete)) {
     $files->{"$local_file"} = 1;
     my $dir_name = $local_file;
     while(1) {
      $dir_name = just_path_name($dir_name);
      last() if(defined($dirs->{"$dir_name"}));
      $dirs->{"$dir_name"} = 1;
      last() if($dir_name eq just_path_name($dir_name));
     };
    };
    return(1) if($self->{force});
    my $date_time_parser = DateTime::Format::RFC3339->new();
    my $local_epoch =  (stat($local_file))[9];
    my $remote_epoch = $date_time_parser->parse_datetime(
     $remote_file->modifiedDate()
    )->epoch();
    if(
     -f($local_file)
     and ($remote_epoch < $local_epoch)
    ) {
     print("skiping [$local_file]...\n");
     return(0);
    } else {
     return(1);
    };
   },
  );
  $google_docs->mirror();
  if(defined($delete)) {
   my($f2d, $d2d) = ([], []);
   find(
    {
     'follow_skip'	=> 2,
     'no_chdir'		=> 1,
     'wanted'		=> sub {
      utf8::decode($_);
      if(-d($_)) {
       push(@$d2d, $_) unless(defined($dirs->{"$_"}));
      } else {
       push(@$f2d, $_) unless(defined($files->{"$_"}));
      };
     },
    },
    $self->{'c'}->{'dstdir'},
   );
   foreach(@$f2d) {
    if(unlink) {
     print("file [$_] removed\n");
    } else {
     warn("because of [$!] unable to remove [$_] file\n");
    };
   };
   foreach(reverse(sort(@$d2d))) {
    if(rmdir) {
     print("folder [$_] removed\n");
    } else {
     warn("because of [$!] unable to remove [$_] folder\n");
    };
   };
  };
 };
 sub DESTROY {
  my $self  = shift();
 };

 # functions:
 sub usage() {
  print(q~
 usage: ~ . $0 . q~ \
  --dstdir /usr/nfs/google-drive/raven428 \
[ --exclude acr \]
[ --delete ]
 ~);
 };
 sub error_and_usage($) {
  my $line = shift();
  $line .= ', Luke!' if($line =~ /use/);
  warn("! error: $line\n");
  usage();
  exit;
 };
 sub just_path_name($) {
  my @folders = split(/\//, shift());
  pop(@folders);
  return(join('/', @folders));
 };
 1;
};

my $my_drive_sync = raven::my_drive_sync->CREATE(
 {
  'debug'		=> 1,
 }
);
$my_drive_sync->run();
undef($my_drive_sync);
