CREATE TABLE requests (
	id SERIAL,
	zone_name varchar(256) NOT NULL,
	inserted TIMESTAMP DEFAULT NOW() NOT NULL,

	PRIMARY KEY (id)
) engine=innodb;
CREATE INDEX zone_name_index ON requests (zone_name);

CREATE USER 'signd'@'localhost' IDENTIFIED BY 'f1234160d518742f758915091e1bca85';
GRANT SELECT,DELETE ON signd.requests TO 'signd'@'localhost' IDENTIFIED BY 'f1234160d518742f758915091e1bca85';
