#!/usr/bin/perl -w

#
# Throw lots of random but interesting test cases at the extended
# Burrows-Wheeler transform builder.
#
# Usage: perl random_tester.pl [rand seed] [# outer iters] [# inner iters]
#

use List::Util qw[min max];

my $seed = 0;
$seed = int $ARGV[0] if defined($ARGV[0]);
srand $seed;

my $outer = 10000;
$outer = int $ARGV[1] if defined($ARGV[1]);
my $limit = $outer;

my $inner = 10;
$inner = int $ARGV[2] if defined($ARGV[2]);

my $tbase = 10;
$tbase = int $ARGV[3] if defined($ARGV[3]);
my $trand = 30;
$trand = int $ARGV[4] if defined($ARGV[4]);

my $pbase = 10;
$pbase = int $ARGV[5] if defined($ARGV[5]);
my $prand = 30;
$prand = int $ARGV[6] if defined($ARGV[6]);

my $verbose = 0;
my $exitOnFail = 1;
my @dnaMap = ('A', 'T', 'C', 'G');

# Utility function generates a random DNA string of the given length
sub randDna($) {
	my $num = shift;
	my $i;
	my $t = '';
	for($i = 0; $i < $num; $i++) {
		$t .= $dnaMap[int(rand(4))];
	}
	return $t;
}

# Trim whitespace from a string argument
sub trim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# Build an Ebwt based on given arguments
sub build {
	my($t, $lineRate, $linesPerSide, $offRate, $ftabChars, $chunkRate, $endian) = @_;
	my $ret = 0;
	
	# Do unpacked version
	my $cmd = "./ebwt_build-with-asserts -d -s -c --lineRate $lineRate --linesPerSide $linesPerSide --offRate $offRate --ftabChars $ftabChars --chunkRate $chunkRate $endian $t .tmp";
	print "$cmd\n";
	my $out = trim(`$cmd 2>&1`);
	if($out eq "") {
		$ret++;
	} else {
		print "$out\n";
		if($exitOnFail) {
			exit 1;
		}
	}

	# Do packed version and assert that it matches unpacked version
	# (sometimes, but not all the time because it takes a while)
	if(int(rand(4)) == 5) {
		$cmd = "./ebwt_build_packed-with-asserts -d -s -c --lineRate $lineRate --linesPerSide $linesPerSide --offRate $offRate --ftabChars $ftabChars --chunkRate $chunkRate $endian $t .tmp.packed";
		print "$cmd\n";
		$out = trim(`$cmd 2>&1`);
		if($out eq "") {
			if(system("diff .tmp.1.ebwt .tmp.packed.1.ebwt") != 0) {
				if($exitOnFail) {
					exit 1;
				}
			} elsif(system("diff .tmp.2.ebwt .tmp.packed.2.ebwt") != 0) {
				if($exitOnFail) {
					exit 1;
				}
			} else {
				$ret++;
			}
		} else {
			print "$out\n";
			if($exitOnFail) {
				exit 1;
			}
		}
	}
	
	return $ret;
}

# Search for a pattern in an existing Ebwt
sub search {
	my($t, $p, $revcomp, $mismatches, $oneHit, $requireResult) = @_;
	if($oneHit) {
		$oneHit = "";
	} else {
		$oneHit = "-a";
	}
	if($mismatches) {
		$mismatches = "-1";
	} else {
		$mismatches = "";
	}
	my $cmd = "./ebwt_search-with-asserts $revcomp $mismatches --orig $t $oneHit -s -c .tmp $p";
	print "$cmd\n";
	my $out = trim(`$cmd 2>.tmp.stderr`);
	
	# Bad exitlevel?
	if($? != 0) {
		print "Exitlevel: $?\n";
		if($exitOnFail) {
			my $err = trim(`cat .tmp.stderr 2> /dev/null`);
			print "Stdout:\n$out\nStderr:\n$err\n";
			exit 1;
		}
		return 0;
	}
	my $err = trim(`cat .tmp.stderr 2> /dev/null`);
	
	# Yielded no results when we were expecting some?
	if($out eq "No results" && $requireResult) {
		print "Expected results but got \"No Results\"\n";
		if($exitOnFail) {
			print "Stdout:\n$out\nStderr:\n$err\n";
			exit 1;
		}
		return 0;
	} elsif($out eq "No results") {
		# Yielded no results, but that's OK
		return 1;
	}
	
	# No output?
	if($out eq "") {
		print "Expected some output but got none\n";
		exit 1 if($exitOnFail);
		return 0;
	}
	
	# Parse output to see if any of it is bad
	my @outlines = split('\n', $out);
	foreach(@outlines) {
		print "$_\n";
		# Result should look like "0:<4,231>,<7,111>,<7,112>,<4,234>"
		if(! /^[0-9]+[-+]?:(<[0-9]+,[0-9]+,[0-9]+>[,]?)+$/) {
			print "$out\n";
			if($exitOnFail) {
				print "Stdout:\n$out\nStderr:\n$err\n";
				exit 1;
			}
			return 0;
		}
	}
	
	# Success
	return 1;
}

my $pass = 0;
my $tests = 0;
my $fail = 0;

for(; $outer > 0; $outer--) {

	# Generate random parameters
	my $lineRate = 4 + int(rand(7));     # Must be >= 4
	my $linesPerSide = 1 + int(rand(3));
	my $offRate = int(rand(16));         # Can be anything
	my $ftabChars = 1 + int(rand(8));    # Must be >= 1
	my $chunkRate = 1 + int(rand(10));   # Must be >= 1
	my $big = int(rand(2));
	my $revcomp = int(rand(2));
	my $endian = '';
	if($big) {
		$endian = "--big";
	} else {
		$endian = "--little";
	}
	if($revcomp) {
		$revcomp = "--revcomp";
	} else {
		$revcomp = "";
	}

	# Generate random text(s)
	my $nt = int(rand(10)) + 1;
	my $t = '';
	for(my $i = 0; $i < $nt; $i++) {
		my $tlen = $tbase + int(rand($trand));
		$t .= randDna($tlen);
		if($i < $nt-1) {
			$t .= ",";
		}
	}
	
	# Run the command to build the Ebwt from the random text
	$pass += build($t, $lineRate, $linesPerSide, $offRate, $ftabChars, $chunkRate, $endian);
	last if(++$tests > $limit);

	my $in = $inner;
	for(; $in >= 0; $in--) {
		# Generate random pattern(s) based on text
		my $pfinal = '';
		my $np = int(rand(10)) + 1;
		for(my $i = 0; $i < $np; $i++) {
			my $pl = int(rand(length($t))) - 10;
			$pl = max($pl, 0);
			$pl = min($pl, length($t));
			my $plen = int(rand($prand)) + $pbase;
			my $pr = min($pl + $plen, length($t));
			my $p = substr $t, $pl, $pr - $pl;
			if(length($p) == 0 || index($p, ",") != -1) {
				$i--; next;
			}
			if(0) {
				# Add some random padding on either side
				my $lpad = randDna(max(0, int(rand(20)) - 10));
				my $rpad = randDna(max(0, int(rand(20)) - 10));
				$p = $lpad . $p . $rpad;
			}
			$pfinal .= $p;
			if($i < $np-1) {
				$pfinal .= ","
			}
		}
		
		# Run the command to search for the pattern from the Ebwt
		my $oneHit = (int(rand(3)) == 0);
		my $mismatches = !(int(rand(3)) == 0);
		$pass += search($t, $pfinal, $revcomp, $mismatches, $oneHit, 1); # require 1 or more results
		last if(++$tests > $limit);
	}

	$in = $inner;
	for(; $in >= 0; $in--) {
		# Generate random pattern *not* based on text
		my $pfinal = '';
		my $np = int(rand(10)) + 1;
		for(my $i = 0; $i < $np; $i++) {
			my $plen = int(rand($prand)) + $pbase;
			my $p = randDna($plen);
			$pfinal .= $p;
			if($i < $np-1) {
				$pfinal .= ","
			}
		}

		# Run the command to search for the pattern from the Ebwt
		my $oneHit = (int(rand(3)) == 0);
		$pass += search($t, $pfinal, $revcomp, $oneHit, 0); # do not require any results
		last if(++$tests > $limit);
	}

	#system("rm -f .tmp.?.ebwt .tmp.packed.?.ebwt");
}

print "$pass tests passed, $fail failed\n";
exit 1 if $fail > 0;
