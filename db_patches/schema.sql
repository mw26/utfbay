GRANT ALL PRIVILEGES ON ubdb.* TO 'mysql'@'localhost' IDENTIFIED BY 'password';

DROP DATABASE IF EXISTS ubdb;
CREATE DATABASE IF NOT EXISTS ubdb;

USE ubdb;

CREATE TABLE IF NOT EXISTS languages (
	id			SMALLINT NOT NULL AUTO_INCREMENT,
	name			CHAR(64),

	PRIMARY KEY 		(id),
	UNIQUE KEY		(name)

) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE latin1_swedish_ci COMMENT 'List of programming languages.';

CREATE TABLE IF NOT EXISTS blobs (
	id 			INT UNSIGNED NOT NULL AUTO_INCREMENT,
	content			TEXT,

	PRIMARY KEY 		(id)

) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE utf8_general_ci COMMENT 'Pastes content.';

CREATE TABLE IF NOT EXISTS publicPastes (
	id 			INT UNSIGNED NOT NULL AUTO_INCREMENT,
	content			INT UNSIGNED NOT NULL,
	lang			SMALLINT NULL,
	timestamp		TIMESTAMP(6) NOT NULL,
	numOfLines		INT UNSIGNED NOT NULL,

	PRIMARY KEY 		(id),
	FOREIGN KEY		(content) REFERENCES blobs(id)
	ON UPDATE RESTRICT
	ON DELETE CASCADE,

	FOREIGN KEY		(lang) REFERENCES languages(id)

) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE latin1_swedish_ci;

CREATE TABLE IF NOT EXISTS privatePastes (
	id 			INT UNSIGNED NOT NULL AUTO_INCREMENT,
	content			INT UNSIGNED NOT NULL,
	lang			SMALLINT NULL,
	timestamp		TIMESTAMP(6) NOT NULL,
	pkey			BINARY (48) NOT NULL,

	PRIMARY KEY 		(id),
	UNIQUE	KEY		(pkey),
	FOREIGN KEY		(content) REFERENCES blobs(id)
	ON UPDATE RESTRICT
	ON DELETE CASCADE,

	FOREIGN KEY		(lang) REFERENCES languages(id)

) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE latin1_swedish_ci;

INSERT INTO languages(name) VALUES
('Ada'),
('C'),
('C++'),
('Pascal'),
('Perl'),
('Ruby');
