#!/usr/bin/env perl

#
# Render speech to text using Google's speech recognition engine.
#
# Copyright (C) 2011 - 2012, Lefteris Zafiris <zaf.000@gmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2. See the COPYING file
# at the top of the source tree.
#
# The script takes as input flac, speex or wav files and returns the following values:
# status     : Return status. 0 means success, non zero values indicating different errors.
# id         : Some id string that googles engine returns, not very useful(?).
# utterance  : The generated text string.
# confidence : A value between 0 and 1 indicating how 'confident' the recognition engine
#  feels about the result. Values bigger than 0.95 usually mean that the
#  resulted text is correct.
#

use strict;
use warnings;
use URI::Escape;
use File::Temp qw(tempfile);
use Getopt::Std;
use File::Basename;
use LWP::UserAgent;
use LWP::ConnCache;

my %options;
my $filetype;
my $audio;
my $ua;
my $url        = "https://www.google.com/speech-api/v1/recognize";
my $samplerate = 8000;
my $language   = "en-US";
my $output     = "detailed";
my $results    = 1;
my $pro_filter = 0;
my $error      = 0;

getopts('l:o:r:n:fhq', \%options);

VERSION_MESSAGE() if (defined $options{h} || !@ARGV);

parse_options();


$ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1});
$ua->agent("Mozilla/5.0 (X11; Linux) AppleWebKit/537.1 (KHTML, like Gecko)");
$ua->env_proxy;
$ua->conn_cache(LWP::ConnCache->new());
$ua->timeout(20);

# send each sound file to google and get the recognition results #
foreach my $file (@ARGV) {
	my ($filename, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
	if ($ext ne ".flac" && $ext ne ".spx" && $ext ne ".wav") {
		say_msg("Unsupported filetype: $ext");
		++$error;
		next;
	}
	if ($ext eq ".flac") {
		$filetype = "x-flac";
	} elsif ($ext eq ".spx") {
		$filetype = "x-speex-with-header-byte";
	} elsif ($ext eq ".wav") {
		$filetype = "x-flac";
		if (($file = encode_flac($file)) eq '-1') {
			++$error;
			next;
		}
	}
	print("Openning $filename\n") if (!defined $options{q});
	if (open(my $fh, "<", "$file")) {
		$audio = do { local $/; <$fh> };
		close($fh);
	} else {
		say_msg("Cant read file $file");
		++$error;
		next;
	}

	$language   = uri_escape($language);
	$pro_filter = uri_escape($pro_filter);
	$results    = uri_escape($results);
	my $response = $ua->post(
		"$url?xjerr=1&client=chromium&lang=$language&pfilter=$pro_filter&maxresults=$results",
		Content_Type => "audio/$filetype; rate=$samplerate",
		Content      => "$audio",
	);
	if (!$response->is_success) {
		say_msg("Failed to get data for file:$file");
		++$error;
		next;
	}
	my %response;
	if ($response->content =~ /^\{"status":(\d*),"id":"([0-9a-z\-]*)","hypotheses":\[(.*)\]\}$/) {
		$response{status} = "$1";
		$response{id}     = "$2";
		if ($response{status} != 0) {
			say_msg("Error reading audio file");
			++$error;
		}

		foreach (split(/,/, $3)) {
			$response{confidence} = $1 if /"confidence":([0-9.]+)/;
			push(@{$response{utterance}}, "$1") if /"utterance":"(.*?)"/gs;
		}
	}
	if ($output eq "detailed") {
		foreach my $key (keys %response) {
			if ($key eq "utterance") {
				printf "%-10s : %s\n", $key, $_ foreach (@{$response{$key}});
			} else {
				printf "%-10s : %s\n", $key, $response{$key};
			}
		}
	} elsif ($output eq "compact") {
		print "$_\n" foreach (@{$response{utterance}});
	} elsif ($output eq "raw") {
		print $response->content;
	}
}

exit(($error) ? 1 : 0);

sub parse_options {
# Command line options parsing #
	if (defined $options{l}) {
	# check if language setting is valid #
		if ($options{l} =~ /^[a-z]{2}(-[a-zA-Z]{2,6})?$/) {
			$language = $options{l};
		} else {
			say_msg("Invalid language setting. Using default.\n");
		}
	}
	if (defined $options{o}) {
	# check if output setting is valid #
		if ($options{o} =~ /^(detailed|compact|raw)$/) {
			$output = $options{o};
		} else {
			say_msg("Invalid output formatting setting. Using default.\n");
		}
	}
	if (defined $options{n}) {
	# set number or results #
		$results = $options{n} if ($options{n} =~ /\d+/);
	}
	if (defined $options{r}) {
	# set audio sampling rate #
		$samplerate = $options{r} if ($options{r} =~ /\d+/);
	}
	# set profanity filter #
	$pro_filter = 2 if (defined $options{f});

	return;
}

sub encode_flac {
# Encode file to flac and return the filename #
	my $file   = shift;
	my $tmpdir = "/tmp";
	my $flac   = `/usr/bin/which flac`;

	if (!$flac) {
		say_msg("flac encoder is missing. Aborting.");
		return -1;
	}
	chomp($flac);

	my ($fh, $tmpname) = tempfile(
		"recg_XXXXXX",
		DIR    => $tmpdir,
		SUFFIX => '.flac',
		UNLINK => 1,
	);
	if (system($flac, "-8", "-f", "--totally-silent", "-o", "$tmpname", "$file")) {
		say_msg("$flac failed to encode file");
		return -1;
	}
	return $tmpname;
}

sub say_msg {
# Print messages to user if 'quiet' flag is not set #
	my @message = @_;
	warn @message if (!defined $options{q});
	return;
}

sub VERSION_MESSAGE {
# Help message #
	print "Speech recognition using google voice API.\n\n",
		"Usage: $0 [options] [file(s)]\n\n",
		"Supported options:\n",
		" -l <lang>      specify the language to use (default 'en-US')\n",
		" -o <type>      specify the type of output fomratting\n",
		"    detailed    print detailed info like confidence and return status (default)\n",
		"    compact     print only the recognized utterance\n",
		"    raw         raw JSON output\n",
		" -r <rate>      specify the audio sample rate in Hz (deafult 8000)\n",
		" -n <number>    specify the maximum number of results (default 1)\n",
		" -f             filter out profanities\n",
		" -q             don't print any error messages or warnings\n",
		" -h             this help message\n\n";
	exit(1);
}
