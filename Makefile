build:
	install -d build/usr/bin/
	rsync -a disk/ build/usr/bin/

clean:
	rm -rf build/
