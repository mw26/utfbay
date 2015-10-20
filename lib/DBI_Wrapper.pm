package DBI_Wrapper; 

$DBI_Wrapper::VERSION= v0.3;

require bytes;

use DBI;
use Digest::SHA qw(sha384_base64);
use MIME::Base64 qw(encode_base64url decode_base64url);
use Time::HiRes qw(gettimeofday);
use POSIX qw(ceil);
use strict;


use constant {
	PR_LANG_SIZE		=> 32,
	INSERT_BLOB		=> 'INSERT INTO blobs (content) VALUES (?);',
	INSERT_PASTE		=> 'INSERT INTO publicPastes (content, lang, numOfLines) VALUES (?, ?, ?);',
	INSERT_PRIV_PASTE	=> 'INSERT INTO privatePastes (content, lang, pkey) VALUES (?, ?, ?);',
	SELECT_PUBLIC_PASTE	=> q(SELECT b.content, l.name language, DATE_FORMAT(p.timestamp, '%M %d, %Y') date, p.id, CHARACTER_LENGTH(b.content) length FROM publicPastes p INNER JOIN blobs b ON p.content=b.id LEFT JOIN languages l ON p.lang=l.id WHERE p.id = ?;),
	SELECT_PRIV_PASTE	=> q(SELECT b.content, l.name language, DATE_FORMAT(p.timestamp, '%M %d, %Y') date, p.id, CHARACTER_LENGTH(b.content) length FROM privatePastes p INNER JOIN blobs b ON p.content=b.id LEFT JOIN languages l ON p.lang=l.id WHERE p.pkey = ?;),
	DATABASE_ERROR		=>  {error => 'Database error. Try again later.'},
	MAX_PASTE_SIZE		=> 65535,
	MAX_PREVIEW_SIZE 	=> 8192, #in symbols
	LINES_IN_PREVIEW	=> 7,
	RECS_PER_PAGE		=> 20,
	SELECT_PAGINATED_REVERS	=> q(SELECT LEFT (SUBSTRING_INDEX(b.content, '\n', ?), ?) content, DATE_FORMAT(p.timestamp, '%k:%i %d %b %Y ') date, p.id, p.numOfLines FROM publicPastes p INNER JOIN blobs b ON p.content=b.id WHERE p.timestamp BETWEEN ? AND DATE_ADD(?, INTERVAL 1 MONTH) ORDER BY p.id  DESC LIMIT ?, 20;),
	SELECT_PAGINATED	=> q(SELECT LEFT (SUBSTRING_INDEX(b.content, '\n', ?), ?) content, DATE_FORMAT(p.timestamp, '%k:%i %d %b %Y ') date, p.id, p.numOfLines FROM publicPastes p INNER JOIN blobs b ON p.content=b.id WHERE p.timestamp BETWEEN ? AND DATE_ADD(?, INTERVAL 1 MONTH) LIMIT ?, 20;),
	SELECT_EPOCH		=> q(SELECT YEAR(timestamp) year, YEAR(timestamp) * 12 + MONTH(timestamp) AS epoch FROM publicPastes ORDER BY id LIMIT 1;),
	SELECT_AVAIL_MONTHS	=> q(SELECT DISTINCT MONTH(timestamp) FROM publicPastes WHERE YEAR(timestamp)= ?;),
	SELECT_MONTHLY_RECS	=> q(SELECT COUNT(id) FROM publicPastes WHERE timestamp BETWEEN ? AND DATE_ADD(?, INTERVAL 1 MONTH)),
};

sub new {
	my $class= shift;
	my %langs= ();
	my %dbStuff= ();

	die 'Hash or hashref with dbname, username and password needed for db connection!' unless defined $_[0];

	if(ref $_[0] eq 'HASH') {
		%dbStuff= %{$_[0]};
	}elsif (ref $_[0] eq '') {
		%dbStuff= @_;
	}

	$dbStuff{attr}= {
		AutoCommit => 0,  # enable transactions, if possible
		RaiseError => 1,
		mysql_enable_utf8 => 1
	};

	my $self= bless {
		dbh	=> undef,
		indCash	=> undef, 
		epoch	=> undef, # oldest record in db: year * 12 + month  
		langs	=> \%langs, # key == lang, val == id in table
		auth	=> \%dbStuff
	};

	$self->__reviveConnection;

	
	eval {
		my $dbh= $self->{dbh};
		my $sth= $dbh->prepare('SELECT  id, name FROM languages;');
		$sth->execute;

		while(my ($id, $lang)= $sth->fetchrow_array) {
			$langs{$lang}= $id;
		}
		$sth= $dbh->prepare(SELECT_EPOCH);
		$sth->execute;

		my $firstYear;
		my $thisYear= (localtime(time))[5] +1900;

		($firstYear, $self->{epoch})= $sth->fetchrow_array;

		my %cash= ();
		
		$sth= $dbh->prepare(SELECT_AVAIL_MONTHS);
		for my $y ($firstYear..$thisYear) {
			$cash{$y}= {};
			$sth->execute($y);
			my $m;

			while ($m= $sth->fetchrow_array) {
				# here we store num of records per this month,
				# but count all at once, may take too long, so
				# count recs only on demand
				$cash{$y}->{$m}= undef;
			}

			if(!keys %{$cash{$y}}) {
				delete $cash{$y};
			}
		}

		$self->{indCash}= \%cash;

	};
	if ($@) {
		die "Can't create wrapper object!\n" .$@;
	}

	return $self;
}

sub __checkLang {
	return undef if length $_[1] > PR_LANG_SIZE;
	
	my ($h, $lang)= @_;
	$h= $h->{langs};
	
	return exists $h->{$lang} ? $h->{$lang} : undef;
}

sub getLangs {

	return [sort {$a cmp $b} keys %{$_[0]->{langs}}];
}

sub __badContent {
	my $pasteRef= $_[-1];

	if (	bytes::length($$pasteRef) > MAX_PASTE_SIZE ) {
		return {error => 'Paste cannot be larger than 64KB!'};

	}
	elsif ( length($$pasteRef) == 0 ) {
		return {error => 'Your paste is empty!'};
	}

	return ();
}

# return structure with error or url to new paste; must be treated as json
sub savePaste {
	my ($self, $pasteRef, $lang, $priv)= @_;
	my $pasteId;
	my $dbh= $self->{dbh};
	my $jsonResp;
	my $url;

	$jsonResp= __badContent($pasteRef) and return $jsonResp;
	$lang= $self->__checkLang($lang);


	$self->__reviveConnection;

	eval {
		local $SIG{'__DIE__'};
		my $blobId= $self->__insertBlob($$pasteRef);
		if($priv eq 'false') {
			$pasteId= $self->__insertPublic($blobId, $lang, $$pasteRef =~ tr/\n// +1);
			$url= "pastes/$pasteId";
		}
		else {
			$pasteId= $self->__insertPrivate($blobId, $lang);
			$url= "private/$pasteId";
		}

		$dbh->commit;
	};

	if ($@) {
		$dbh->rollback;
		return DATABASE_ERROR;
	}
	else {
		return {redirect => $url};
	}

}

sub getPaste {
	my ($self, $id, $priv) = @_;

	$self->__reviveConnection;
	my $dbh= $self->{dbh};
	my $row;
	my $sth;

	eval {
		if(!defined $priv) {
			$sth= $dbh->prepare(SELECT_PUBLIC_PASTE);
			$id+= 0;

			$sth->execute($id);
		}
		else {
			$sth= $dbh->prepare(SELECT_PRIV_PASTE);
			$sth->execute(decode_base64url($id));
		}

		$row= $sth->fetchrow_hashref();
	};
	if ($@) {
		return DATABASE_ERROR;
	}
	elsif (!defined $row) {
		return {error => "Paste $id doesn't exists! Why not create a new one?"};
	}

	$row->{lines}= $row->{content} =~ tr/\n// +1;

	return $row;
}

sub __insertPrivate {
	my ($self, $blobId, $langId)= @_;

	my $dbh= $self->{dbh};
	
	my $digest= sha384_base64(gettimeofday());
	$digest =~ tr\+/\-_\;
	$digest;

	$dbh->do(INSERT_PRIV_PASTE, undef, $blobId, $langId,  decode_base64url($digest)) or die $DBI::errstr;
	return $digest;
}

sub __countMonthlyRecs {
	my ($self, $year, $mon)= @_;

	my $cash= $self->{indCash};
	
	if(!exists $cash->{$year}) {
		return 0;
	}

	$cash= $cash->{$year};

	if(!exists $cash->{$mon}) {
		return 0;
	}

	if(!defined $cash->{$mon}) {
		my $ts= sprintf("%d-%02d-01 00:00:00", $year, $mon);

		my $dbh= $self->{dbh};
		my $sth= $dbh->prepare(SELECT_MONTHLY_RECS) or die $DBI::errstr;
		$sth->execute(($ts) x 2) or die $DBI::errstr;
		$cash->{$mon}= $sth->fetchrow_array() or die $DBI::errstr;
	}

	return $cash->{$mon};
}

sub __incCashValue {
	my ($self, $year, $mon)= @_;

	my $cash= $self->{indCash};

	if(!exists $cash->{$year}) {
		$cash->{$year}= {};
	}
	$cash= $cash->{$year};

	if(!exists $cash->{$mon}) {
		$cash->{$mon}= 1;
	}elsif(defined $cash->{$mon}) {
		$cash->{$mon}++;
	}
}

sub __insertPublic {
	my ($self, $blobId, $langId, $numOfLines)= @_;

	my $dbh= $self->{dbh};
	$dbh->do(INSERT_PASTE, undef, $blobId, $langId, $numOfLines) or die $DBI::errstr;

	my ($mon, $year)= (localtime(time))[4,5];
	$year+= 1900;
	$mon++;

	# For mysql driver parameters are ignored.

	$self->__incCashValue($year, $mon);

	return $dbh->last_insert_id((undef) x 4);
}

sub __insertBlob {
	my $self= shift;

	my $dbh= $self->{dbh};
	$dbh->do(INSERT_BLOB, undef, @_) or die $DBI::errstr;

	return $dbh->last_insert_id((undef) x 4);
}

sub __reviveConnection {
	my $self= pop;
	my $dbh= $self->{dbh};
	my $dbStuff= $self->{auth};

	if(!defined $dbh || !$dbh->ping) {
		$dbh= DBI->connect(
			'dbi:mysql:'.$dbStuff->{dbname},
			$dbStuff->{username},
		       	$dbStuff->{password},
			$dbStuff->{attr}
		) or die $DBI::errstr;

		$self->{dbh}= $dbh;
	}
}

sub __getIndex {
	my ($self, $year)= @_;
	my $cash= $self->{indCash};

	my @years= sort {$a <=> $b} keys %{$cash};
	my @months= sort {$a <=> $b} keys %{$cash->{$year}};

	if(@years and @months) {
		return {years => \@years, months => \@months};
	}
	else {
		return undef;
	}
}

sub __recentYear {
	my $cash= $_[0]->{indCash};
	return (sort {$b <=> $a} keys %{$cash})[0];
}

sub getPaginatedPage {
	my $self= shift;
	my ($year, $mon, $page)= map {$_ + 0} @_;
	my $mainQuery= SELECT_PAGINATED;

	my ($tMon, $tYear)= (localtime(time))[4,5];
	$tMon++;
	$tYear+= 1900;

	# no params, get most recent month and year
	if(!$year) {
		$year= $self->__recentYear;
		$mon= -1;
		$mainQuery= SELECT_PAGINATED_REVERS;
	}
	elsif ($tYear == $year and $tMon == $mon) {
		$mainQuery= SELECT_PAGINATED_REVERS;
	}

	my $index= $self->__getIndex($year);
	
	if(!$mon) {
		$mon= $index->{months}[0];
	}elsif ($mon == -1) {
		$mon= $index->{months}[-1];
	}

	my $index= $self->__getIndex($year);

	$self->__reviveConnection;
	my $dbh= $self->{dbh};
	my ($sth, $recs);
	my ($totalRecs, $totalPages);

	eval {
		local $SIG{'__DIE__'};
		$totalRecs= $self->__countMonthlyRecs($year, $mon);
		$totalPages= ceil($totalRecs / RECS_PER_PAGE);
		if($totalRecs == 0 or $totalPages < $page) {
			$recs= undef;
		}
		else {
			$sth= $dbh->prepare($mainQuery);
			my $ts= sprintf("%d-%02d-01 00:00:00", $year, $mon);
			$sth->execute(LINES_IN_PREVIEW, MAX_PREVIEW_SIZE, ($ts) x 2, RECS_PER_PAGE * $page);
			$recs= $sth->fetchall_arrayref();
		}
	};

	if ($@) {
		return DATABASE_ERROR;
	}
	elsif (!defined $recs or @$recs == 0) {
		return {error => "Can't find any acceptable record!"};
	}

	foreach my $e (@$recs) {
		push @$e, $$e[0] =~ tr/\n// +1;
	}

	return {
			vals	=> $recs,
		       	index	=> $self->__getIndex($year),
		       	month	=> $mon,
		       	year	=> $year,
		       	page	=> $page,
			url	=> "/pastes/$year/$mon/$page",
			totalPages => $totalPages,
		};

}

1;
