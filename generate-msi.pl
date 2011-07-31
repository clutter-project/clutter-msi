#!/usr/bin/perl

use warnings;
use strict;

use Getopt::Long;
use Fcntl ':mode';
use File::Basename;

my $package_version;

{
    my $id = 1;
    sub get_id
    {
        return "Id" . $id++;
    }
}

sub scan_folder
{
    my ($dir) = @_;
    my $dir_handle;
    my @files;

    opendir $dir_handle, $dir or die("Failed to open $dir");

    while (my $short_name = readdir($dir_handle))
    {
        if (!($short_name =~ /^\./))
        {
            my $full_name = "$dir/$short_name";
            my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
                $atime, $mtime, $ctime, $blksize, $blocks)
                = stat($full_name);

            my %file = ("id" => get_id(),
                        "name" => $short_name);

            if (S_ISDIR ($mode))
            {
                my @children = scan_folder($full_name);
                $file{children} = \@children;
                $file{type} = "directory";
            }
            else
            {
                $file{type} = "file";
            }

            push(@files, \%file);
        }
    }

    closedir $dir_handle;

    @files;
}

sub encode_entities
{
    my ($text) = @_;

    my %map = ("&" => "amp",
               "\"" => "quot",
               "'" => "apos",
               "<" => "lt",
               ">" => "gt");

    $text =~ s/[&'<>"]/"&".$map{$&}.";"/eg;

    return $text;
}

sub dump_directories
{
    my ($files, $indentation) = @_;

    for my $file (@$files)
    {
        if ($file->{type} eq "directory")
        {
            print("$indentation" .
                  "<Directory Id='" . encode_entities($file->{id}) . "' " .
                  "Name='" . encode_entities($file->{name}) . "'>\n");
            dump_directories($file->{children},
                             "$indentation  ");
            print("$indentation</Directory>\n");
        }
    }
}

sub dump_directories_for_features
{
    my ($features, $indentation) = @_;

    for my $feature (@$features)
    {
        dump_directories($feature->{files}, $indentation);
    }
}

sub dump_files
{
    my ($base_dir, $parent_id, $all_files, $indentation) = @_;
    my @dirs = ();
    my @files = ();

    for my $file (@$all_files)
    {
        if ($file->{type} eq "directory")
        {
            push(@dirs, $file);
        }
        else
        {
            push(@files, $file);
        }
    }

    if (@files > 0)
    {
        print($indentation .
              "<DirectoryRef Id='" . encode_entities($parent_id) . "'>\n");
        for my $file (@files)
        {
            print("$indentation  " .
                  "<Component Id='" . encode_entities($file->{id}) . "' " .
                  "Guid='*'>\n" .
                  "$indentation    " .
                  "<File Id='" . encode_entities($file->{id}) . "' " .
                  "Source='" .
                  encode_entities($base_dir . "/" . $file->{name}) . "' " .
                  "Name='" . encode_entities($file->{name}) . "' " .
                  "KeyPath='yes' />\n" .
                  "$indentation  </Component>\n");
        }
        print("$indentation</DirectoryRef>\n");
    }

    for my $file (@dirs)
    {
        dump_files("$base_dir/$file->{name}",
                   $file->{id},
                   $file->{children},
                   $indentation);
    }
}

sub dump_files_for_features
{
    my ($features, $indentation) = @_;

    for my $feature (@$features)
    {
        dump_files($feature->{directory}, "APPLICATIONROOTDIRECTORY",
                   $feature->{files}, $indentation);
    }
}

sub dump_components
{
    my ($files, $indentation) = @_;

    for my $file (@$files)
    {
        if ($file->{type} eq "directory")
        {
            dump_components($file->{children}, $indentation);
        }
        else
        {
            print($indentation .
                  "<ComponentRef Id='" .
                  encode_entities($file->{id}) . "' />\n");
        }
    }
}

sub dump_features
{
    my ($features, $indentation) = @_;

    for my $feature (@$features)
    {
        print($indentation .
              "<Feature Id='" . encode_entities($feature->{id}) . "' " .
              "Title='" . encode_entities($feature->{name}) . "' " .
              "Level='1'>\n");
        dump_components($feature->{files}, "$indentation  ");
        print("$indentation</Feature>\n");
    }
}

sub process_template
{
    my ($features, $template_name) = @_;

    open(my $file, "<", $template_name)
        or die("Couldn't open $template_name");

    while (my $line = <$file>)
    {
        if ($line =~ /^(.*)@([a-zA-Z0-9_]+)@(.*)$/)
        {
            my $indentation = $1;

            if ($2 eq "DIRECTORIES")
            {
                dump_directories_for_features($features, $indentation);
            }
            elsif ($2 eq "FILES")
            {
                dump_files_for_features($features, $indentation);
            }
            elsif ($2 eq "FEATURES")
            {
                dump_features($features, $indentation);
            }
            elsif ($2 eq "PACKAGE_VERSION")
            {
                die ("Missing --packageversion option")
                    unless defined($package_version);
                print("$1" . encode_entities($package_version) . "$3\n");
            }
            else
            {
                die("Unknown marker $1");
            }
        }
        else
        {
            print($line);
        }
    }

    close($file);
}

GetOptions("packageversion=s" => \$package_version)
    or exit(1);

# The rest of the arguments should be of the form
# <FeatureName>:<Directory> to specify each feature. Alternatively
# the feature can be omitted to make it the same as the directory

my @features = ();

for my $feature_desc (@ARGV)
{
    my ($feature_name, $feature_dir) = split (/:/, $feature_desc);
    my %feature;

    $feature_dir = $feature_name unless defined($feature_dir);

    %feature = ( name => $feature_name,
                 directory => $feature_dir,
                 id => get_id ());
    push(@features, \%feature);
}

for my $feature (@features)
{
    my @files = scan_folder($feature->{directory});
    $feature->{files} = \@files;
}

process_template(\@features,
                 dirname ($0) . "/clutter.wxs.in");
