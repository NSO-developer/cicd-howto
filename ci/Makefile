all:
	for f in packages/*/src; do \
	$(MAKE) -C $$f all || exit 1; \
	done
	$(MAKE) netsim

netsim:
	ncs-netsim create-network ./packages/router 3 ex --dir ./netsim

release: all
	mkdir -p release
	for f in packages/*; do \
	hash=`git rev-parse --short HEAD`;\
	tar cfz release/`basename $$f`-$$hash.tgz --exclude=src -C packages `basename $$f`;\
	done

clean:
	for f in packages/*/src; do \
	$(MAKE) -C $$f clean || exit 1; \
	done
	rm -rf packages/s1
	rm -rf ./netsim logs/* state/* ncs-cdb/*.cdb
	rm -rf release
