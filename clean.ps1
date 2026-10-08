$msg = (git log -1 --format=%B) -join "`n"; $msg = $msg -replace "(?m)^Co-authored-by: arena-agent.*$",""; $msg | Set-Content commit.txt; git commit --amend -F commit.txt
