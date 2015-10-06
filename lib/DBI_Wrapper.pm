package DBI_Wrapper; 

require bytes;

$DBI_Wrapper::VERSION= v0.05;

use strict;
use DBI;

use constant {
	PR_LANG_SIZE		=> 32,
	INSERT_BLOB_SQL		=> 'INSERT INTO blobs (content) VALUES (?);',
	INSERT_PASTE_SQL	=> 'INSERT INTO publicPastes (content, lang) VALUES (?, ?);',
	SELECT_PUBLIC_PASTE	=> 'SELECT b.content, l.name, p.timestamp FROM publicPastes p
					INNER JOIN blobs b ON p.content=b.id
					LEFT JOIN languages l ON p.lang=l.id
				    WHERE p.id = ?;',
	MAX_PASTE_SIZE => 65535
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
		RaiseError => 1
	};

	my $self= bless {
		dbh	=> undef,
		langs	=> \%langs, #key == lang, val == id in table
		auth	=> \%dbStuff
	};

	$self->__reviveConnection;


	my $sth= $self->{dbh}->prepare('SELECT  id, name FROM languages;') or die $DBI::errstr;
	$sth->execute or die $DBI::errstr;

	while(my ($id, $lang)= $sth->fetchrow_array) {
		$langs{$lang}= $id;
	}

	return $self;
}

sub __checkLang {
	return undef if length $_[1] > PR_LANG_SIZE;
	
	my ($self, $lang)= @_;
	
	return exists $self->{langs}->{$lang} ? $lang : undef;
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

#return structure with error or url to new paste, must be treated as json
sub savePaste {
	my ($self, $pasteRef, $lang)= @_;
	my $pasteId;
	my $dbh= $self->{dbh};
	my $jsonResp;

	$jsonResp= __badContent($pasteRef) and return $jsonResp;
	$lang= $self->__checkLang($lang);


	$self->__reviveConnection;

	eval {
		local $SIG{'__DIE__'};
		my $blobId= $self->__insertBlob($$pasteRef) or die $DBI::errstr;
		$pasteId= $self->__insertPaste($blobId, $lang) or die $DBI::errstr;
		$dbh->commit;
	};

	if ($@) {
		$dbh->rollback;
		return {error => 'Database error. Try again later.'};
	}
	else {
		return {redirect => "/pastes/$pasteId"};
	}

}

sub __insertPaste {
	my $self= shift;
	my $blobId= $_[0];
	my $langId= undef;

	if(defined $_[1]) {
       		$langId= $self->{langs}->{$_[1]};
	}

	my $dbh= $self->{dbh};
	$dbh->do(INSERT_PASTE_SQL, undef, $blobId, $langId) or die $DBI::errstr;
	
	#For mysql driver parameters are ignored.
	return $dbh->last_insert_id((undef) x 4);
}

sub __insertBlob {
	my $self= shift;

	my $dbh= $self->{dbh};
	$dbh->do(INSERT_BLOB_SQL, undef, @_) or die $DBI::errstr;

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

1;
