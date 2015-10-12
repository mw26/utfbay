package DBI_Wrapper; 

require bytes;

use MIME::Base64 qw(encode_base64url decode_base64url);
use Time::HiRes qw(gettimeofday);
use Digest::SHA qw(sha384_base64);

$DBI_Wrapper::VERSION= v0.1;
use strict;
use DBI;

use constant {
	PR_LANG_SIZE		=> 32,
	INSERT_BLOB_SQL		=> 'INSERT INTO blobs (content) VALUES (?);',
	INSERT_PASTE_SQL	=> 'INSERT INTO publicPastes (content, lang) VALUES (?, ?);',
	INSERT_PRIV_PASTE_SQL	=> 'INSERT INTO privatePastes (content, lang, pkey) VALUES (?, ?, ?);',
	SELECT_PUBLIC_PASTE	=> q(SELECT b.content, l.name language, DATE_FORMAT(p.timestamp, '%M %d, %Y') date, p.id, CHARACTER_LENGTH(b.content) length
       	FROM publicPastes p
					INNER JOIN blobs b ON p.content=b.id
					LEFT JOIN languages l ON p.lang=l.id
				    WHERE p.id = ?;),
	SELECT_PRIV_PASTE	=> q(SELECT b.content, l.name language, DATE_FORMAT(p.timestamp, '%M %d, %Y') date, p.id, CHARACTER_LENGTH(b.content) length
       	FROM privatePastes p
					INNER JOIN blobs b ON p.content=b.id
					LEFT JOIN languages l ON p.lang=l.id
				    WHERE p.pkey = ?;),
	DATABASE_ERROR		=>  {error => 'Database error. Try again later.'},
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
		RaiseError => 1,
		mysql_enable_utf8 => 1
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

#return structure with error or url to new paste; must be treated as json
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
			$pasteId= $self->__insertPublic($blobId, $lang);
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

	$dbh->do(INSERT_PRIV_PASTE_SQL, undef, $blobId, $langId,  decode_base64url($digest)) or die $DBI::errstr;
	return $digest;
}

sub __insertPublic {
	my ($self, $blobId, $langId)= @_;

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
