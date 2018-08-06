#!/usr/bin/perl
#
#
#
#
#

use strict;
use Data::Dumper;
use DBI;

my $user = shift;
my $password = shift;

my $type = shift;

my $search_like = shift;

my $dsn = "DBI:mysql:database=mysql;mysql_socket=/var/run/mysql/mysql.sock"
my $tmp_file = '/tmp/zbx_mysql.status';
my $zbx_sender_file = '/tmp/zbx_mysql.sender';
my $max_updated = 10;

my $result = 0;

my $dbh;

if ($type eq 'all')
{
    $result = update_all();
}
elsif ($type eq 'life') {
    $result = update_all('0');
}
elsif ($type eq 'lld') {
    $result = generate_lld($search_like);
}
elsif ($type eq 'database-data') {
    $result = db_size($search_like);
} 
elsif ($type eq 'lld-tables') {
    $result = generate_lld_tables($search_like);
}
else {
    $result = get_variable($type);
}

# Disconnect from the database.
$dbh->disconnect() if defined $dbh;

print $result;
exit;

sub get_status($$) {
    my $variable_name = shift;
    my $strong = shift;

    my $result = {};

    $result = get_global_status($variable_name, $strong);

    return $result if defined($result) and defined($strong);

    $result = merge_hash($result, get_variables($variable_name, $strong));

    return $result if defined($result) and defined($strong);

    $result = merge_hash($result, get_innodb_status($variable_name, $strong));

    return $result if defined($result) and defined($strong);

    $result = merge_hash($result, get_slave_status($variable_name, $strong));
    
    return $result if defined($result) and defined($strong);

    $result = merge_hash($result, get_master_status($variable_name, $strong));
    
    return $result if defined($result) and defined($strong);

    $result = merge_hash($result, get_process_stats($variable_name, $strong));
                                                               
    return $result if defined($result) and defined($strong);

    my $tmp = {};
    foreach my $name (keys %{$result}) {
	my $value = $result->{$name};

	$result->{$name} = 1 if (uc($value) eq 'YES' or uc($value) eq 'ON' );
        $result->{$name} = 0 if (uc($value) eq 'NO' or uc($value) eq 'OFF');

	unless ( defined($tmp->{uc($name)})) {
	    $tmp->{uc($name)} = 1;
	}
	else {
	    delete $result->{$name};
	}
    }


    return $result;
}

sub get_global_status($$) {
    my $variable_name = shift;                                 
    my $strong = shift;                                        
    
    my $result = {};

    my $query_status = 'SHOW /*!50002 GLOBAL */ STATUS';

    $query_status = $query_status.' like \'%'.$variable_name.'%\'' if (defined($variable_name) and !defined($strong));
    $query_status = $query_status.' like \''.$variable_name.'\'' if (defined($variable_name) and defined($strong));

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;

    my $sth = $dbh->prepare($query_status);

    $sth->execute();
    
    while (my $ref = $sth->fetchrow_hashref()) {
        my $name = $ref->{'Variable_name'};
        my $value = $ref->{'Value'};
        
        $result->{$name} = $value;
    }
    
    $sth->finish();

    return $result;
}

sub get_variables($$) {
    my $variable_name = shift;
    my $strong = shift;

    my $result = {};

    my $query_variables = 'SHOW GLOBAL VARIABLES';

    $query_variables = $query_variables.' like \'%'.$variable_name.'%\'' if (defined($variable_name) and !defined($strong));
    $query_variables = $query_variables.' like \''.$variable_name.'\'' if (defined($variable_name) and defined($strong));

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;        

    my $sth = $dbh->prepare($query_variables);
    
    $sth->execute();
    
    while (my $ref = $sth->fetchrow_hashref()) {
        my $name = $ref->{'Variable_name'};
        my $value = $ref->{'Value'};

        $value = 1 if ($value eq 'YES' or $value eq 'ON');
        $value = 0 if ($value eq 'NO' or $value eq 'OFF');
    
        $result->{$name} = $value;
    }
    
    $sth->finish();

    return $result;
}

sub get_master_status($$) {
    my $variable_name = shift;
    my $strong = shift;

    my $result = {};

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;

    my $sth = $dbh->prepare('SHOW MASTER LOGS');
                                                               
    $sth->execute();                                           
                                                               
    while (my $ref = $sth->fetchrow_hashref()) { 
	$result->{'binary_log_space'} += $ref->{'File_size'} if defined($ref->{'File_size'}) and $ref->{'File_size'} > 0;
    }
    
    $sth->finish();

    return $result;
}

sub get_slave_status($$) {
    my $variable_name = shift;
    my $strong = shift;
    
    my $result = {};

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;

    my $sth = $dbh->prepare('SHOW SLAVE STATUS');

    $sth->execute();

    my $row = $sth->fetchrow_hashref();

    $sth->finish();

    $row->{'Seconds_Behind_Master'} = '' if defined($row->{'Seconds_Behind_Master'}) and $row->{'Seconds_Behind_Master'} eq 'NULL';

    $result = $row if defined $row;

    return $result;
}

sub get_process_stats() {
    my $variable_name = shift;                                 
    my $strong = shift;

    my $result = {
	'State_closing_tables' => 0,
	'State_Copying_to_tmp_table' => 0,
	'State_end' => 0,
	'State_freeing_items' => 0,
	'State_Locked' => 0,
	'State_Reading_from_net' => 0,
	'State_Sending_data' => 0,
	'State_Sorting_result' => 0,
	'State_statistics' => 0,
	'State_storing_result_in_query_cache' => 0,
	'State_Writing_to_net' => 0,
	'State_preparing' => 0,
	'State_checking_permissions' => 0,
	'State_checking_query_cache_for_query' => 0,
	'State_converting_HEAP_to_MyISAM' => 0,
	'State_Copying_to_tmp_table_on_disk' => 0,
	'State_Creating_tmp_table' => 0,
	'State_idle' => 0,
	'State_init' => 0,
	'State_logging_slow_query' => 0,
	    'State_Opening_tables' => 0,
	    'State_optimizing' => 0,
	    'State_other' => 0,
	    'State_query_end' => 0,
	    'State_removing_tmp_table' => 0,
	    'State_System_lock' => 0,
	    'State_update' => 0,
	    'State_Updating' => 0,
	};

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;

    my $sth = $dbh->prepare('SHOW PROCESSLIST');

    $sth->execute();

    while (my $ref = $sth->fetchrow_hashref()) {
	next if ($ref->{'State'} eq 'Connecting to master');
	next if ($ref->{'State'} =~ /Slave has read all relay log/);

	$result->{'State_idle'}++ if $ref->{'State'} eq '';
	next if $ref->{'State'} eq '';

	$ref->{'State'} =~ s/^(Table lock|Waiting for .*lock)$/Locked/i;
	$ref->{'State'} =~ s/\s/_/g;

	if (is_required('State_'.$ref->{'State'}) != -1) {
	    $result->{'State_'.$ref->{'State'}}++;
	}
	else {
	    $result->{'State_other'}++;
	}        
    }

    $sth->finish();

    return $result;
}

sub get_innodb_status($$) {
    my $variable_name = shift;
    my $strong = shift;

    my $result = {};

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;

    my $sth = $dbh->prepare('SHOW /*!50000 ENGINE*/ INNODB STATUS');

    $sth->execute();

    my $innodb = $sth->fetchrow();

    $sth->finish();


    return parse_innodb_data($innodb);
}

sub generate_lld($) {
    my $like = shift;

    my $first = 1;
    my $result;

    my $list = get_status($like,undef);

    $result = "{\n";
    $result .= "\t\"data\":[\n\n";

    foreach my $name (sort keys %{$list}) {
        $result .= "\t,\n" if not $first;
	$first = 0;
    
        $result .= "\t{\n";
	$result .= "\t\t\"{#MYSQL_NAME}\":\"$name\",\n";
        $result .= "\t\t\"{#MYSQL_VALUE}\":\"$list->{$name}\"\n";
	$result .= "\t\t\"{#MYSQL_TYPE}\":\"numeric\"\n" if ($list->{$name} =~ /^\d+$/);
	$result .= "\t\t\"{#MYSQL_TYPE}\":\"string\"\n" unless ($list->{$name} =~ /^\d+$/);
	$result .= "\t}\n";
    }

    $result .= "\n\t]\n";
    $result .= "}\n";

    return $result;
}

sub db_size($) {
    my $db_name = shift;

    $dbh = DBI->connect($dsn, $user, $password) unless defined $dbh;
    
    my $sth = $dbh->prepare("SELECT SUM(data_length + index_length) as size FROM information_schema.tables WHERE table_schema = '$db_name'");

    $sth->execute();

    my $row = $sth->fetchrow_hashref();

    $sth->finish();

    return defined($row->{'size'}) ? $row->{'size'} : 0;
}

sub generate_lld_tables($) {

}

sub get_variable($) {
    my $search = shift;

    my $var = get_status($search, 1);

    return $var->{$search} || '';
}

sub update_all($) {
    my $type = shift;
    my $result;

    my $last_updated = 0;

    if (-e $tmp_file) {
	$last_updated = (stat($tmp_file))[9];
    }

    my $data;

    my $tmp = "$last_updated < ".time." - $max_updated";

    if ($last_updated < (time - $max_updated)) {
	$data = get_status(undef, undef);

	open(FILE_STAT, "> $tmp_file");

	foreach my $name (sort keys %{$data}) {
	    my $value = $data->{$name};

	    print FILE_STAT $name."\t".$value."\n" if $value ne '';
	}

	close(FILE_STAT);

	chmod 0777, $tmp_file;
    }
    else {
	open(FILE_STAT, "< $tmp_file");

	while(<FILE_STAT>) {
	    my $str = $_;

	    if ($str =~ /^(.+)\t(.+)$/) {
		$data->{$1} = $2;
	    }
	}
    }

    return send_data($data, $type);
}

sub merge_hash($$) {
    my $part1 = shift;
    my $part2 = shift;

    my $result = {}; 
    foreach my $name (keys %{$part1}) {
	$result->{$name} = $part1->{$name};
    }

    foreach my $name (keys %{$part2}) {
        $result->{$name} = $part2->{$name};
    }

    return ($result);
}

sub send_data($) {
    my $data = shift;
    my $type = shift;

    my $cnt = scalar %{$data};

    return $cnt if ($cnt == 0);


    open(SENDER, '> '. $zbx_sender_file);

    foreach my $name (sort keys %{$data}) {
	next if !defined $data->{$name} or $data->{$name} eq '';
	next if is_required($name) eq -1 or (defined($type) and is_required($name) != $type);

        $data->{$name} = '"'.$data->{$name}.'"' if ($data->{$name} !=~/^\d+$/);

	print SENDER "- mysql[$name] $data->{$name}\n";
    }

    close(SENDER);

    my $result = `zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -i /tmp/zbx_mysql.sender`;

    foreach my $value (split(/\n/, $result)) {
	if ($value =~ /sent\:\s(\d+)\;.+/) {
	    $cnt = $1;
	}
    }

    unlink($zbx_sender_file);

    return $cnt;
}

sub is_required($) {
    my $name = shift;
    
    my $names = {
'Aborted_clients' => 0,                                                                                                               
'Aborted_connects' => 0,                                                                                                              
'binary_log_space' => 0,                                                                                                              
'Binlog_cache_disk_use' => 0,                                                                                                         
'Binlog_cache_use' => 0,                                                                                                              
'Binlog_stmt_cache_disk_use' => 0,                                                                                                    
'Binlog_stmt_cache_use' => 0,                                                                                                         
'Bytes_received' => 0,                                                                                                                
'Bytes_sent' => 0,                                                                                                                    
'Com_admin_commands' => 0,                                                                                                            
'Com_alter_db' => 0,                                                                                                                  
'Com_alter_db_upgrade' => 0,                                                                                                          
'Com_alter_event' => 0,                                                                                                               
'Com_alter_function' => 0,                                                                                                            
'Com_alter_procedure' => 0,                                                                                                           
'Com_alter_server' => 0,                                                                                                              
'Com_alter_tablespace' => 0,                                                                                                          
'Com_alter_table' => 0,                                                                                                               
'Com_analyze' => 0,                                                                                                                   
'Com_assign_to_keycache' => 0,                                                                                                        
'Com_begin' => 0,                                                                                                                     
'Com_binlog' => 0,                                                                                                                    
'Com_call_procedure' => 0,                                                                                                            
'Com_change_db' => 0,                                                                                                                 
'Com_change_master' => 0,                                                                                                             
'Com_checksum' => 0,                                                                                                                  
'Com_check' => 0,                                                                                                                     
'Com_commit' => 0,                                                                                                                    
'Com_create_db' => 0,                                                                                                                 
'Com_create_event' => 0,                                                                                                              
'Com_create_function' => 0,                                                                                                           
'Com_create_index' => 0,                                                                                                              
'Com_create_procedure' => 0,                                                                                                          
'Com_create_server' => 0,                                                                                                             
'Com_create_table' => 0,                                                                                                              
'Com_create_trigger' => 0,                                                                                                            
'Com_create_udf' => 0,                                                                                                                
'Com_create_user' => 0,                                                                                                               
'Com_create_view' => 0,                                                                                                               
'Com_dealloc_sql' => 0,                                                                                                               
'Com_delete' => 0,                                                                                                                    
'Com_delete_multi' => 0,                                                                                                              
'Com_do' => 0,                                                                                                                        
'Com_drop_db' => 0,                                                                                                                   
'Com_drop_event' => 0,                                                                                                                
'Com_drop_function' => 0,                                                                                                             
'Com_drop_index' => 0,                                                                                                                
'Com_drop_procedure' => 0,                                                                                                            
'Com_drop_server' => 0,                                                                                                               
'Com_drop_table' => 0,                                                                                                                
'Com_drop_trigger' => 0,                                                                                                              
'Com_drop_user' => 0,                                                                                                                 
'Com_drop_view' => 0,                                                                                                                 
'Com_empty_query' => 0,                                                                                                               
'Com_execute_sql' => 0,                                                                                                               
'Com_flush' => 0,                                                                                                                     
'Com_grant' => 0,                                                                                                                     
'Com_ha_close' => 0,                                                                                                                  
'Com_ha_open' => 0,                                                                                                                   
'Com_ha_read' => 0,                                                                                                                   
'Com_help' => 0,                                                                                                                      
'Com_insert' => 0,                                                                                                                    
'Com_insert_select' => 0,                                                                                                             
'Com_install_plugin' => 0,                                                                                                            
'Com_kill' => 0,                                                                                                                      
'Com_load' => 0,                                                                                                                      
'Com_lock_tables' => 0,                                                                                                               
'Com_optimize' => 0,                                                                                                                  
'Com_preload_keys' => 0,                                                                                                              
'Com_prepare_sql' => 0,                                                                                                               
'Com_purge' => 0,                                                                                                                     
'Com_purge_before_date' => 0,                                                                                                         
'Com_release_savepoint' => 0,                                                                                                         
'Com_rename_table' => 0,                                                                                                              
'Com_rename_user' => 0,                                                                                                               
'Com_repair' => 0,                                                                                                                    
'Com_replace' => 0,                                                                                                                   
'Com_replace_select' => 0,                                                                                                            
'Com_reset' => 0,                                                                                                                     
'Com_resignal' => 0,                                                                                                                  
'Com_revoke' => 0,                                                                                                                    
'Com_revoke_all' => 0,                                                                                                                
'Com_rollback' => 0,                                                                                                                  
'Com_rollback_to_savepoint' => 0,                                                                                                     
'Com_savepoint' => 0,                                                                                                                 
'Com_select' => 0,                                                                                                                    
'Com_set_option' => 0,                                                                                                                
'Com_show_authors' => 0,                                                                                                              
'Com_show_binlogs' => 0,                                                                                                              
'Com_show_binlog_events' => 0,                                                                                                        
'Com_show_charsets' => 0,                                                                                                             
'Com_show_client_statistics' => 0,                                                                                                    
'Com_show_collations' => 0,                                                                                                           
'Com_show_contributors' => 0,                                                                                                         
'Com_show_create_db' => 0,                                                                                                            
'Com_show_create_event' => 0,                                                                                                         
'Com_show_create_func' => 0,                                                                                                          
'Com_show_create_proc' => 0,                                                                                                          
'Com_show_create_table' => 0,                                                                                                         
'Com_show_create_trigger' => 0,                                                                                                       
'Com_show_databases' => 0,                                                                                                            
'Com_show_engine_logs' => 0,                                                                                                          
'Com_show_engine_mutex' => 0,                                                                                                         
'Com_show_engine_status' => 0,                                                                                                        
'Com_show_errors' => 0,                                                                                                               
'Com_show_events' => 0,                                                                                                               
'Com_show_fields' => 0,                                                                                                               
'Com_show_function_status' => 0,                                                                                                      
'Com_show_grants' => 0,                                                                                                               
'Com_show_index_statistics' => 0,                                                                                                     
'Com_show_keys' => 0,                                                                                                                 
'Com_show_master_status' => 0,                                                                                                        
'Com_show_open_tables' => 0,                                                                                                          
'Com_show_plugins' => 0,                                                                                                              
'Com_show_privileges' => 0,                                                                                                           
'Com_show_procedure_status' => 0,                                                                                                     
'Com_show_processlist' => 0,                                                                                                          
'Com_show_profiles' => 0,                                                                                                             
'Com_show_profile' => 0,                                                                                                              
'Com_show_relaylog_events' => 0,                                                                                                      
'Com_show_slave_hosts' => 0,                                                                                                          
'Com_show_slave_status' => 0,                                                                                                         
'Com_show_slave_status_nolock' => 0,                                                                                                  
'Com_show_status' => 0,                                                                                                               
'Com_show_storage_engines' => 0,                                                                                                      
'Com_show_tables' => 0,                                                                                                               
'Com_show_table_statistics' => 0,                                                                                                     
'Com_show_table_status' => 0,                                                                                                         
'Com_show_temporary_tables' => 0,                                                                                                     
'Com_show_thread_statistics' => 0,                                                                                                    
'Com_show_triggers' => 0,                                                                                                             
'Com_show_user_statistics' => 0,                                                                                                      
'Com_show_variables' => 0,                                                                                                            
'Com_show_warnings' => 0,                                                                                                             
'Com_signal' => 0,                                                                                                                    
'Com_slave_start' => 0,                                                                                                               
'Com_slave_stop' => 0,                                                                                                                
'Com_stmt_close' => 0,                                                                                                                
'Com_stmt_execute' => 0,                                                                                                              
'Com_stmt_fetch' => 0,                                                                                                                
'Com_stmt_prepare' => 0,                                                                                                              
'Com_stmt_reprepare' => 0,                                                                                                            
'Com_stmt_reset' => 0,                                                                                                                
'Com_stmt_send_long_data' => 0,                                                                                                       
'Com_truncate' => 0,                                                                                                                  
'Com_uninstall_plugin' => 0,                                                                                                          
'Com_unlock_tables' => 0,                                                                                                             
'Com_update' => 0,                                                                                                                    
'Com_update_multi' => 0,                                                                                                              
'Com_xa_commit' => 0,                                                                                                                 
'Com_xa_end' => 0,                                                                                                                    
'Com_xa_prepare' => 0,                                                                                                                
'Com_xa_recover' => 0,                                                                                                                
'Com_xa_rollback' => 0,                                                                                                               
'Com_xa_start' => 0,                                                                                                                  
'Connections' => 0,                                                                                                                   
'Created_tmp_disk_tables' => 0,                                                                                                       
'Created_tmp_files' => 0,                                                                                                             
'Created_tmp_tables' => 0,                                                                                                            
'Delayed_errors' => 0,                                                                                                                
'Delayed_insert_threads' => 0,                                                                                                        
'Delayed_writes' => 0,                                                                                                                
'Flush_commands' => 0,                                                                                                                
'Flush_commands' => 0,                                                                                                                
'Handler_commit' => 0,                                                                                                                
'Handler_delete' => 0,                                                                                                                
'Handler_discover' => 0,                                                                                                              
'Handler_prepare' => 0,                                                                                                               
'Handler_read_first' => 0,                                                                                                            
'Handler_read_key' => 0,                                                                                                              
'Handler_read_last' => 0,                                                                                                             
'Handler_read_next' => 0,                                                                                                             
'Handler_read_prev' => 0,                                                                                                             
'Handler_read_rnd' => 0,                                                                                                              
'Handler_read_rnd_next' => 0,                                                                                                         
'Handler_rollback' => 0,                                                                                                              
'Handler_savepoint' => 0,                                                                                                             
'Handler_savepoint_rollback' => 0,                                                                                                    
'Handler_update' => 0,                                                                                                                
'Handler_write' => 0,                                                                                                                 
'innodb_active_transactions' => 0,                                                                                                    
'innodb_adaptive_hash_memory' => 0,                                                                                                   
'innodb_additional_pool_alloc' => 0,                                                                                                  
'innodb_current_transactions' => 0,                                                                                                   
'innodb_database_pages' => 0,                                                                                                         
'innodb_file_fsyncs' => 0,                                                                                                            
'innodb_file_reads' => 0,                                                                                                             
'innodb_file_system_memory' => 0,                                                                                                     
'innodb_file_writes' => 0,                                                                                                            
'innodb_free_pages' => 0,                                                                                                             
'innodb_hash_index_cells_total' => 0,                                                                                                 
'innodb_hash_index_cells_used' => 0,                                                                                                  
'innodb_last_checkpoint' => 0,                                                                                                        
'innodb_locked_transactions' => 0,                                                                                                    
'innodb_lock_system_memory' => 0,                                                                                                     
'innodb_log_bytes_flushed' => 0,                                                                                                      
'innodb_log_bytes_written' => 0,                                                                                                      
'innodb_modified_pages' => 0,                                                                                                         
'innodb_page_hash_memory' => 0,                                                                                                       
'innodb_pending_aio_log_ios' => 0,                                                                                                    
'innodb_pending_aio_sync_ios' => 0,                                                                                                   
'innodb_pending_buf_pool_flushes' => 0,                                                                                               
'innodb_pending_chkp_writes' => 0,                                                                                                    
'innodb_pending_ibuf_aio_reads' => 0,                                                                                                 
'innodb_pending_log_flushes' => 0,                                                                                                    
'innodb_pending_log_writes' => 0,                                                                                                     
'innodb_pending_normal_aio_reads' => 0,                                                                                               
'innodb_pending_normal_aio_writes' => 0,                                                                                              
'innodb_pool_size' => 0,                                                                                                              
'innodb_queries_inside' => 0,                                                                                                         
'innodb_queries_queued' => 0,                                                                                                         
'innodb_read_views' => 0,                                                                                                             
'innodb_recovery_system_memory' => 0,                                                                                                 
'innodb_spin_rounds' => 0,                                                                                                            
'innodb_spin_waits' => 0,                                                                                                             
'innodb_uncheckpointed_bytes' => 0,                                                                                                   
'innodb_unflushed_log' => 0,                                                                                                          
'innodb_unpurged_txns' => 0,                                                                                                          
'Key_blocks_not_flushed' => 0,                                                                                                        
'Key_blocks_unused' => 0,                                                                                                             
'Key_blocks_used' => 0,                                                                                                               
'Key_reads' => 0,                                                                                                                     
'Key_read_requests' => 0,                                                                                                             
'Key_writes' => 0,                                                                                                                    
'Key_write_requests' => 0,                                                                                                            
'Max_used_connections' => 0,                                                                                                          
'Not_flushed_delayed_rows' => 0,                                                                                                      
'Opened_files' => 0,                                                                                                                  
'Opened_tables' => 0,                                                                                                                 
'Opened_table_definitions' => 0,                                                                                                      
'Open_files' => 0,                                                                                                                    
'Open_streams' => 0,                                                                                                                  
'Open_tables' => 0,                                                                                                                   
'Open_table_definitions' => 0,                                                                                                        
'Prepared_stmt_count' => 0,                                                                                                           
'Qcache_free_blocks' => 0,                                                                                                            
'Qcache_free_memory' => 0,                                                                                                            
'Qcache_hits' => 0,                                                                                                                   
'Qcache_inserts' => 0,                                                                                                                
'Qcache_lowmem_prunes' => 0,                                                                                                          
'Qcache_not_cached' => 0,                                                                                                             
'Qcache_queries_in_cache' => 0,                                                                                                       
'Qcache_total_blocks' => 0,                                                                                                           
'Queries' => 0,                                                                                                                       
'Questions' => 0,                                                                                                                     
'Select_full_join' => 0,                                                                                                              
'Select_full_join' => 0,                                                                                                              
'Select_full_range_join' => 0,                                                                                                        
'Select_full_range_join' => 0,                                                                                                        
'Select_range' => 0,                                                                                                                  
'Select_range' => 0,                                                                                                                  
'Select_range_check' => 0,                                                                                                            
'Select_range_check' => 0,                                                                                                            
'Select_scan' => 0,                                                                                                                   
'Select_scan' => 0,                                                                                                                   
'Slave_heartbeat_period' => 0,                                                                                                        
'Slave_open_temp_tables' => 0,                                                                                                        
'Slave_received_heartbeats' => 0,                                                                                                     
'Slave_retried_transactions' => 0,                                                                                                    
'Slow_launch_threads' => 0,                                                                                                           
'Slow_queries' => 0,                                                                                                                  
'Sort_merge_passes' => 0,                                                                                                             
'Sort_range' => 0,                                                                                                                    
'Sort_rows' => 0,                                                                                                                     
'Sort_scan' => 0,                                                                                                                     
'State_closing_tables' => 0,
'State_Copying_to_tmp_table' => 0,
'State_end' => 0,
'State_freeing_items' => 0,
'State_Locked' => 0,
'State_Reading_from_net' => 0,
'State_Sending_data' => 0,
'State_Sorting_result' => 0,
'State_statistics' => 0,
'State_storing_result_in_query_cache' => 0,
'State_Writing_to_net' => 0,
'State_preparing' => 0,
'State_checking_permissions' => 0,                                                                                                    
'State_checking_query_cache_for_query' => 0,                                                                                          
'State_converting_HEAP_to_MyISAM' => 0,                                                                                               
'State_Copying_to_tmp_table_on_disk' => 0,                                                                                            
'State_Creating_tmp_table' => 0,                                                                                                      
'State_idle' => 0,                                                                                                                    
'State_init' => 0,                                                                                                                    
'State_logging_slow_query' => 0,                                                                                                      
'State_Opening_tables' => 0,                                                                                                          
'State_optimizing' => 0,                                                                                                              
'State_other' => 0,                                                                                                                   
'State_query_end' => 0,                                                                                                               
'State_removing_tmp_table' => 0,                                                                                                      
'State_System_lock' => 0,                                                                                                             
'State_update' => 0,                                                                                                                  
'State_Updating' => 0,                                                                                                                
'Table_locks_immediate' => 0,                                                                                                         
'Table_locks_waited' => 0,                                                                                                            
#		'Tc_log_page_size' => 0,                                                                                                             
'Tc_log_page_waits' => 0,                                                                                                             
'autocommit' => 1,
'automatic_sp_privileges' => 1,
'big_tables' => 1,
'binlog_cache_size' => 1,
'binlog_direct_non_transactional_updates' => 1,
'binlog_format' => 1,
'binlog_stmt_cache_size' => 1,
'bulk_insert_buffer_size' => 1,
'connect_timeout' => 1,
'default_storage_engine' => 1,
'delayed_insert_limit' => 1,
'delayed_insert_timeout' => 1,
'delayed_queue_size' => 1,
'delay_key_write' => 1,
'dictionary_cache_memory' => 1,
'div_precision_increment' => 1,
#		'engine_condition_pushdown' => 1,
'event_scheduler' => 1,
#		'expand_fast_index_creation' => 1,
'expire_logs_days' => 1,
'flush' => 1,
'flush_time' => 1,
'foreign_key_checks' => 1,
'ft_max_word_len' => 1,
'ft_min_word_len' => 1,
'ft_query_expansion_limit' => 1,
'general_log' => 1,
'group_concat_max_len' => 1,
'have_compress' => 1,
'have_crypt' => 1,
'have_csv' => 1,
'have_dynamic_loading' => 1,
'have_geometry' => 1,
'have_innodb' => 1,
'have_ndbcluster' => 1,
'have_partitioning' => 1,
'have_profiling' => 1,
'have_query_cache' => 1,
'have_rtree_keys' => 1,
'have_ssl' => 1,
'have_symlink' => 1,
'hostname' => 1,
'init_connect' => 1,
'init_file' => 1,
'init_slave' => 1,
#		'innodb_adaptive_flushing_method' => 1,
'innodb_change_buffering' => 1,
#		'innodb_corrupt_table_action' => 1,
'innodb_read_ahead' => 1,
'innodb_stats_method' => 1,
'innodb_version' => 1,
'interactive_timeout' => 1,
'join_buffer_size' => 1,
'key_buffer_size' => 1,
'key_cache_age_threshold' => 1,
'key_cache_block_size' => 1,
'key_cache_division_limit' => 1,
'large_files_support' => 1,
'large_pages' => 1,
'large_page_size' => 1,
'local_infile' => 1,
'locked_in_memory' => 1,
'lock_wait_timeout' => 1,
'log' => 1,
'log_bin' => 1,
'log_bin_trust_function_creators' => 1,
'log_queries_not_using_indexes' => 1,
'log_slave_updates' => 1,
'log_slow_admin_statements' => 1,
'log_slow_filter' => 1,
'log_slow_queries' => 1,
'log_slow_rate_limit' => 1,
#		'log_slow_slave_statements' => 1,
#		'log_slow_sp_statements' => 1,
'log_slow_verbosity' => 1,
'log_warnings' => 1,
'log_warnings_suppress' => 1,
'long_query_time' => 1,
'lower_case_file_system' => 1,
'lower_case_table_names' => 1,
'low_priority_updates' => 1,
'max_allowed_packet' => 1,
#		'max_binlog_cache_size' => 1,
'max_binlog_size' => 1,
#		'max_binlog_stmt_cache_size' => 1,
'max_connections' => 1,
'max_connect_errors' => 1,
'max_delayed_threads' => 1,
'max_error_count' => 1,
'max_heap_table_size' => 1,
#		'max_join_size' => 1,
'max_length_for_sort_data' => 1,
#		'max_long_data_size' => 1,
'max_prepared_stmt_count' => 1,
'max_relay_log_size' => 1,
#		'max_seeks_for_key' => 1,
'max_sort_length' => 1,
'max_sp_recursion_depth' => 1,
'max_user_connections' => 1,
#		'max_write_lock_count' => 1,
'min_examined_row_limit' => 1,
#		'multi_range_count' => 1,
'myisam_data_pointer_size' => 1,
'myisam_max_sort_file_size' => 1,
'myisam_mmap_size' => 1,
'myisam_recover_options' => 1,
'myisam_repair_threads' => 1,
'myisam_sort_buffer_size' => 1,
'myisam_stats_method' => 1,
'myisam_use_mmap' => 1,
'net_buffer_length' => 1,
'net_read_timeout' => 1,
'net_retry_count' => 1,
'net_write_timeout' => 1,
#		'old_alter_table' => 1,
'old_passwords' => 1,
'open_files_limit' => 1,
'optimizer_prune_level' => 1,
'optimizer_search_depth' => 1,
#		'optimizer_switch' => 1,
'port' => 1,
'preload_buffer_size' => 1,
'profiling' => 1,
'profiling_history_size' => 1,
'protocol_version' => 1,
'query_alloc_block_size' => 1,
'query_cache_limit' => 1,
'query_cache_min_res_unit' => 1,
'query_cache_size' => 1,
'query_cache_strip_comments' => 1,
'query_cache_type' => 1,
'query_cache_wlock_invalidate' => 1,
'query_prealloc_size' => 1,
'query_response_time_range_base' => 1,
'query_response_time_stats' => 1,
'range_alloc_block_size' => 1,
'read_buffer_size' => 1,
'read_only' => 1,
'read_rnd_buffer_size' => 1,
'relay_log_purge' => 1,
'relay_log_recovery' => 1,
'relay_log_space_limit' => 1,
'report_port' => 1,
'secure_auth' => 1,
'server_id' => 1,
'skip_external_locking' => 1,
'skip_name_resolve' => 1,
'skip_networking' => 1,
'skip_show_database' => 1,
'slave_compressed_protocol' => 1,
'slave_exec_mode' => 1,
'slave_net_timeout' => 1,
'slave_skip_errors' => 1,
'slave_transaction_retries' => 1,
#		'slave_type_conversions' => 1,
'slow_launch_time' => 1,
'slow_query_log' => 1,
'slow_query_log_timestamp_always' => 1,
#		'slow_query_log_timestamp_precision' => 1,
#		'slow_query_log_use_global_control' => 1,
'sort_buffer_size' => 1,
#		'sql_auto_is_null' => 1,
'sql_buffer_result' => 1,
'sql_log_bin' => 1,
'sql_log_off' => 1,
'sql_mode' => 1,
'sql_notes' => 1,
'sql_quote_show_create' => 1,
'sql_safe_updates' => 1,
#		'sql_select_limit' => 1,
'sql_slave_skip_counter' => 1,
'sql_warnings' => 1,
'storage_engine' => 1,
'sync_binlog' => 1,
'sync_frm' => 1,
'sync_master_info' => 1,
'sync_relay_log' => 1,
'sync_relay_log_info' => 1,
'system_time_zone' => 1,
'table_definition_cache' => 1,
'table_open_cache' => 1,
'thread_handling' => 1,
'timed_mutexes' => 1,
'time_zone' => 1,
'tmp_table_size' => 1,
'total_mem_alloc' => 1,
'transaction_alloc_block_size' => 1,
'transaction_prealloc_size' => 1,
'tx_isolation' => 1,
'unique_checks' => 1,
'updatable_views_with_limit' => 1,
'userstat' => 1,
'version' => 1,
'wait_timeout' => 1,
'Uptime' => 0,
'innodb_history_list' => 0,
'Uptime_since_flush_status' => 0,
'Slave_running' => 0,
'ignore_builtin_innodb' => 1,
'innodb_adaptive_flushing' => 1,
'Innodb_adaptive_hash_cells' => 0,
'Innodb_adaptive_hash_heap_buffers' => 0,
'innodb_adaptive_hash_index' => 1,
'innodb_adaptive_hash_index_partitions' => 1,
'Innodb_adaptive_hash_non_hash_searches' => 0,
'innodb_additional_mem_pool_size' => 1,
'innodb_autoextend_increment' => 1,
'innodb_autoinc_lock_mode' => 1,
'Innodb_background_log_sync' => 0,
'innodb_blocking_buffer_pool_restore' => 1,
'innodb_buffer_pool_instances' => 1,
'Innodb_buffer_pool_pages_data' => 0,
'Innodb_buffer_pool_pages_dirty' => 0,
'Innodb_buffer_pool_pages_flushed' => 0,
'Innodb_buffer_pool_pages_free' => 0,
'Innodb_buffer_pool_pages_LRU_flushed' => 0,
'Innodb_buffer_pool_pages_made_not_young' => 0,
'Innodb_buffer_pool_pages_made_young' => 0,
'Innodb_buffer_pool_pages_misc' => 0,
'Innodb_buffer_pool_pages_old' => 0,
'Innodb_buffer_pool_pages_total' => 0,
'Innodb_buffer_pool_reads' => 0,
'Innodb_buffer_pool_read_ahead' => 0,
'Innodb_buffer_pool_read_ahead_evicted' => 0,
'Innodb_buffer_pool_read_ahead_rnd' => 0,
'Innodb_buffer_pool_read_requests' => 0,
'innodb_buffer_pool_restore_at_startup' => 1,
'innodb_buffer_pool_size' => 1,
'Innodb_buffer_pool_wait_free' => 0,
'Innodb_buffer_pool_write_requests' => 0,
'Innodb_checkpoint_age' => 0,
'innodb_checkpoint_age_target' => 1,
'Innodb_checkpoint_max_age' => 0,
'Innodb_checkpoint_target_age' => 0,
'innodb_checksums' => 1,
'innodb_commit_concurrency' => 1,
'innodb_concurrency_tickets' => 1,
'Innodb_current_row_locks' => 0,
'Innodb_data_fsyncs' => 0,
'Innodb_data_pending_fsyncs' => 0,
'Innodb_data_pending_reads' => 0,
'Innodb_data_pending_writes' => 0,
'Innodb_data_read' => 0,
'Innodb_data_reads' => 0,
'Innodb_data_writes' => 0,
'Innodb_data_written' => 0,
'Innodb_dblwr_pages_written' => 0,
'Innodb_dblwr_writes' => 0,
'Innodb_deadlocks' => 0,
'innodb_dict_size_limit' => 1,
'Innodb_dict_tables' => 0,
'innodb_doublewrite' => 1,
'innodb_fake_changes' => 1,
'innodb_fast_checksum' => 1,
'innodb_fast_shutdown' => 1,
'innodb_file_format' => 1,
'innodb_file_format_check' => 1,
'innodb_file_per_table' => 1,
'innodb_flush_log_at_trx_commit' => 1,
'innodb_flush_method' => 1,
'Threads_cached' => 0,
'Threads_connected' => 0,
'Threads_created' => 0,
'Threads_running' => 0,
'thread_stack' => 1,
'thread_cache_size' => 1,
#'thread_concurrency' => 1,
'thread_hash_memory' => 1,
'innodb_flush_neighbor_pages' => 1,
'innodb_force_load_corrupted' => 1,
'innodb_force_recovery' => 1,
'Innodb_have_atomic_builtins' => 1,
'Innodb_history_list_length' => 0,
'innodb_ibuf_accel_rate' => 1,
'innodb_ibuf_active_contract' => 1,
'Innodb_ibuf_discarded_deletes' => 0,
'Innodb_ibuf_discarded_delete_marks' => 0,
'Innodb_ibuf_discarded_inserts' => 0,
'Innodb_ibuf_free_list' => 0,
'innodb_ibuf_max_size' => 1,
'Innodb_ibuf_merged_deletes' => 0,
'Innodb_ibuf_merged_delete_marks' => 0,
'innodb_large_prefix' => 1,
'innodb_kill_idle_transaction' => 1,
'innodb_io_capacity' => 1,
'innodb_import_table_from_xtrabackup' => 1,
'Innodb_ibuf_size' => 0,
'Innodb_ibuf_segment_size' => 0,
'Innodb_ibuf_merges' => 0,
'Innodb_ibuf_merged_inserts' => 0,
'innodb_lazy_drop_table' => 1,
'innodb_locked_tables' => 0,
'innodb_locks_unsafe_for_binlog' => 1,
'innodb_lock_structs' => 0,
'innodb_lock_wait_secs' => 0,
'innodb_lock_wait_timeout' => 1,
'innodb_log_block_size' => 1,
'innodb_log_buffer_size' => 1,
'innodb_log_files_in_group' => 1,
'innodb_log_file_size' => 1,
'Innodb_log_waits' => 0,
'Innodb_log_writes' => 0,
'Innodb_log_write_requests' => 0,
'Innodb_lsn_current' => 0,
'Innodb_lsn_flushed' => 0,
'Innodb_lsn_last_checkpoint' => 0,
'Innodb_master_thread_1_second_loops' => 0,
'Innodb_master_thread_10_second_loops' => 0,
'Innodb_master_thread_background_loops' => 0,
'Innodb_master_thread_main_flush_loops' => 0,
'Innodb_master_thread_sleeps' => 0,
'innodb_max_dirty_pages_pct' => 1,
'innodb_max_purge_lag' => 1,
'Innodb_max_trx_id' => 0,
'Innodb_mem_adaptive_hash' => 0,
'Innodb_mem_dictionary' => 0,
'Innodb_mem_total' => 0,
'Innodb_mem_total' => 0,
'Innodb_mutex_os_waits' => 0,
'Innodb_mutex_spin_rounds' => 0,
'Innodb_mutex_spin_waits' => 0,
'Innodb_oldest_view_low_limit_trx_id' => 0,
'innodb_old_blocks_pct' => 1,
'innodb_old_blocks_time' => 1,
'innodb_open_files' => 1,
'Innodb_os_log_fsyncs' => 0,
'Innodb_os_log_pending_fsyncs' => 0,
'Innodb_os_log_pending_writes' => 0,
'Innodb_os_log_written' => 0,
'innodb_os_waits' => 0,
'Innodb_pages_created' => 0,
'Innodb_pages_read' => 0,
'Innodb_pages_written' => 0,
'innodb_page_size' => 1,
'innodb_purge_batch_size' => 1,
'innodb_purge_threads' => 1,
'Innodb_purge_trx_id' => 0,
'Innodb_purge_undo_no' => 0,
'innodb_random_read_ahead' => 1,
'innodb_read_ahead_threshold' => 1,
'innodb_read_io_threads' => 1,
'innodb_recovery_stats' => 1,
'innodb_recovery_update_relay_log' => 1,
'innodb_replication_delay' => 1,
'innodb_rollback_on_timeout' => 1,
'innodb_rollback_segments' => 1,
'Innodb_rows_deleted' => 0,
'Innodb_rows_inserted' => 0,
'Innodb_rows_read' => 0,
'Innodb_rows_updated' => 0,
'Innodb_row_lock_current_waits' => 0,
'Innodb_row_lock_time' => 0,
'Innodb_row_lock_time_avg' => 0,
'Innodb_row_lock_time_max' => 0,
'Innodb_row_lock_waits' => 0,
'innodb_sem_waits' => 0,
'innodb_sem_wait_time_ms' => 0,
'innodb_show_locks_held' => 1,
'innodb_show_verbose_locks' => 1,
'innodb_spin_wait_delay' => 1,
'innodb_stats_auto_update' => 1,
'innodb_stats_on_metadata' => 1,
'innodb_stats_sample_pages' => 1,
'innodb_stats_update_need_lock' => 1,
'innodb_strict_mode' => 1,
'innodb_support_xa' => 1,
'innodb_sync_spin_loops' => 1,
'Innodb_s_lock_os_waits' => 0,
'Innodb_s_lock_spin_rounds' => 0,
'Innodb_s_lock_spin_waits' => 0,
'innodb_table_locks' => 1,
'innodb_thread_concurrency' => 1,
'innodb_thread_concurrency_timer_based' => 1,
'innodb_thread_sleep_delay' => 1,
'innodb_transactions' => 0,
'Innodb_truncated_status_writes' => 0,
'innodb_use_global_flush_log_at_trx_commit' => 1,
'innodb_use_native_aio' => 1,
'innodb_use_sys_malloc' => 1,
'innodb_use_sys_stats_table' => 1,
'innodb_write_io_threads' => 1,
'Innodb_x_lock_os_waits' => 0,
'Innodb_x_lock_spin_rounds' => 0,
'Flashcache_enabled' => 1,
# Replication
'Slave_IO_State' => 0,
'Master_Host' => 0,
'Connect_Retry' => 0,
'Master_Log_File' => 0,
'Read_Master_Log_Pos' => 0,
'Relay_Log_File' => 0,
'Relay_Log_Pos' => 0,
'Relay_Master_Log_File' => 0,
'Slave_IO_Running' => 0,
'Slave_SQL_Running' => 0,
'Replicate_Do_DB' => 0,
'Replicate_Ignore_DB' => 0,
'Replicate_Do_Table' => 0,
'Replicate_Ignore_Table' => 0,
'Replicate_Wild_Do_Table' => 0,                                                     
'Replicate_Wild_Ignore_Table' => 0,                                                 
'Last_Errno' => 0,                                                                  
'Last_Error' => 0,                                                    
'Skip_Counter' => 0,                                                  
'Exec_Master_Log_Pos' => 0,                                           
'Relay_Log_Space' => 0,                                               
'Until_Condition' => 0,                                               
'Until_Log_File' => 0,                                                
'Until_Log_Pos' => 0,                                                 
'Master_SSL_Allowed' => 0,                                            
'Seconds_Behind_Master' => 0,                                         
'Last_IO_Errno' => 0,
'Last_IO_Error' => 0,
'Last_SQL_Errno' => 0,
'Last_SQL_Error' => 0,
'Replicate_Ignore_Server_Ids' => 0,
'Master_Server_Id' => 0,
		};

    foreach my $val (%{$names}) {
	return $names->{$val} if uc($val) eq uc($name);
    }


    return -1;
}

sub parse_innodb_data($) {
    my $innodb = shift;

    my $results  = {
	    'innodb_spin_waits' => [ ],
	    'innodb_spin_rounds' => [ ],
	    'innodb_os_waits' => [ ],
	    'innodb_sem_waits' => '',
	    'innodb_sem_wait_time_ms' => '',
	    'innodb_transactions' => '',
	    'innodb_transactions' => '',
	    'innodb_history_list' => '',
	    'innodb_current_transactions' => '',
	    'innodb_active_transactions' => '',
	    'innodb_lock_wait_secs' => '',
	    'innodb_read_views' => '',
	    'innodb_locked_tables' => '',
	    'innodb_lock_structs' => '',
	    'innodb_locked_transactions' => '',
	    'innodb_lock_structs' => '',
	    'innodb_file_reads' => '',
	    'innodb_file_writes' => '',
	    'innodb_file_fsyncs' => '',
	    'innodb_pending_normal_aio_reads' => '',
	    'innodb_pending_normal_aio_writes' => '',
	    'innodb_pending_ibuf_aio_reads' => '',
	    'innodb_pending_aio_log_ios' => '',
	    'innodb_pending_aio_sync_ios' => '',
	    'innodb_pending_log_flushes' => '',
	    'innodb_pending_buf_pool_flushes' => '',
	    'innodb_ibuf_used_cells' => '',
	    'innodb_ibuf_free_cells' => '',
	    'innodb_ibuf_cell_count' => '',
	    'innodb_ibuf_used_cells' => '',
	    'innodb_ibuf_free_cells' => '',
	    'innodb_ibuf_cell_count' => '',
	    'innodb_ibuf_merges' => '',
	    'innodb_ibuf_inserts' => '',
	    'innodb_ibuf_merged' => '',
	    'innodb_ibuf_inserts' => '',
	    'innodb_ibuf_merged' => '',
	    'innodb_ibuf_merges' => '',
	    'innodb_hash_index_cells_total' => '',
	    'innodb_hash_index_cells_used' => '',
	    'innodb_log_writes' => '',
	    'innodb_pending_log_writes' => '',
	    'innodb_pending_chkp_writes' => '',
	    'innodb_log_bytes_written' => '',
	    'innodb_log_bytes_flushed' => '',
	    'innodb_last_checkpoint' => '',
	    'innodb_total_mem_alloc' => '',
	    'innodb_additional_pool_alloc' => '',
	    'innodb_adaptive_hash_memory' => '',
	    'innodb_page_hash_memory' => '',
	    'innodb_dictionary_cache_memory' => '',
	    'innodb_file_system_memory' => '',
	    'innodb_lock_system_memory' => '',
	    'innodb_recovery_system_memory' => '',
	    'innodb_thread_hash_memory' => '',
	    'innodb_io_pattern_memory' => '',
	    'innodb_pool_size' => '',
	    'innodb_free_pages' => '',
	    'innodb_database_pages' => '',
	    'innodb_modified_pages' => '',
	    'innodb_pages_read' => '',
	    'innodb_pages_created' => '',
	    'innodb_pages_written' => '',
	    'innodb_rows_inserted' => '',
	    'innodb_rows_updated' => '',
	    'innodb_rows_deleted' => '',
	    'innodb_rows_read' => '',
	    'innodb_queries_inside' => '',
	    'innodb_queries_queued' => '',
	    'innodb_log_bytes_flushed' => '',
	    'innodb_last_checkpoint' => '',
	    'innodb_unflushed_log' => '',
	    'innodb_uncheckpointed_bytes' => '',
    };

    my $txn_seen = 0;

    my $prev_line;

    my @innodb_arr = split(/\n/, $innodb);

    foreach my $line (@innodb_arr) {
	chomp($line);

	$line =~ s/^\s+//;
	$line =~ s/\s+$//;

	my @row = split(/\,*\s+/, $line);

      # SEMAPHORES
	if (index($line, 'Mutex spin waits') != -1 ) {
	    # Mutex spin waits 1747, rounds 10440, OS waits 148
	    # Mutex spin waits 0, rounds 247280272495, OS waits 316513438

	    push @{$results->{'innodb_spin_waits'}}, $row[3];
	    push @{$results->{'innodb_spin_rounds'}}, $row[5];
    	    push @{$results->{'innodb_os_waits'}}, $row[8];
      }
      elsif (index($line, 'RW-shared spins') != -1 and index($line, ';') > 0 ) {
         # RW-shared spins 3859028, OS waits 2100750; RW-excl spins 4641946, OS waits 1530310

	    push @{$results->{'innodb_spin_waits'}}, $row[2];
	    push @{$results->{'innodb_spin_waits'}}, $row[8];
    	    push @{$results->{'innodb_os_waits'}}, $row[5];
    	    push @{$results->{'innodb_os_waits'}}, $row[11];
      }
      elsif (index($line, 'RW-shared spins') != -1 && index($line, '; RW-excl spins') == -1) {
         # Post 5.5.17 SHOW ENGINE INNODB STATUS syntax
         # RW-shared spins 604733, rounds 8107431, OS waits 241268

	    push @{$results->{'innodb_spin_waits'}}, $row[2];
	    push @{$results->{'innodb_os_waits'}}, $row[7];
      }
      elsif (index($line, 'RW-excl spins') != -1) {
         # Post 5.5.17 SHOW ENGINE INNODB STATUS syntax
         # RW-excl spins 604733, rounds 8107431, OS waits 241268

	    push @{$results->{'innodb_spin_waits'}}, $row[2];
            push @{$results->{'innodb_os_waits'}}, $row[7];
      }
      elsif (index($line, 'seconds the semaphore:') > 0) {
         # --Thread 907205 has waited at handler/ha_innodb.cc line 7156 for 1.00 seconds the semaphore:

	    $results->{'innodb_sem_waits'}++;
	    $results->{'innodb_sem_wait_time_ms'} = $results->{'innodb_sem_wait_time_ms'} + $row[9] * 1000;
      }

      # TRANSACTIONS
      elsif ( index($line, 'Trx id counter') != -1 ) {
         # The beginning of the TRANSACTIONS section: start counting
         # transactions
         # Trx id counter 0 1170664159
         # Trx id counter 861B144C
         $results->{'innodb_transactions'} = make_bigint(
            $row[3], (defined($row[4]) ? $row[4] : ''));
	    $txn_seen = 1;
      }
      elsif ( index($line, 'Purge done for trx') != -1 ) {
         # Purge done for trx's n:o < 0 1170663853 undo n:o < 0 0
         # Purge done for trx's n:o < 861B135D undo n:o < 0
         my $purged_to = make_bigint($row[6], $row[7] eq 'undo' ? '' : $row[7]);
         $results->{'innodb_unpurged_txns'} = $results->{'innodb_transactions'} - $purged_to;
      }
      elsif (index($line, 'History list length') != -1 ) {
         # History list length 132
	    $results->{'innodb_history_list'} = $row[3];
      }
      elsif ( $txn_seen && index($line, '---TRANSACTION') != -1 ) {
         # ---TRANSACTION 0, not started, process no 13510, OS thread id 1170446656
	    $results->{'innodb_current_transactions'}++;
         if ( index($line, 'ACTIVE') > 0 ) {
	    $results->{'innodb_active_transactions'}++;
         }
      }
      elsif ( $txn_seen && index($line, '------- TRX HAS BEEN') != -1 ) {
	# ------- TRX HAS BEEN WAITING 32 SEC FOR THIS LOCK TO BE GRANTED:
	$results->{'innodb_lock_wait_secs'}++;
      }
      elsif ( index($line, 'read views open inside InnoDB') > 0 ) {
         # 1 read views open inside InnoDB
         $results->{'innodb_read_views'} = $row[0];
      }
      elsif ( index($line, 'mysql tables in use') != -1 ) {
         # mysql tables in use 2, locked 2
	    $results->{'innodb_lock_wait_secs'} += $row[4];
	    $results->{'innodb_locked_tables'} += $row[6];
      }
      elsif ( $txn_seen && index($line, 'lock struct(s)') > 0 ) {
         # 23 lock struct(s), heap size 3024, undo log entries 27
         # LOCK WAIT 12 lock struct(s), heap size 3024, undo log entries 5
         # LOCK WAIT 2 lock struct(s), heap size 368
         if ( index($line, 'LOCK WAIT') != -1 ) {
	    $results->{'innodb_lock_structs'} += $row[2];
	    $results->{'innodb_locked_transactions'}++;
         }
         else {
	    $results->{'innodb_lock_structs'} += $row[0];
         }
      }

      # FILE I/O
      elsif (index($line, ' OS file reads, ') > 0 ) {
         # 8782182 OS file reads, 15635445 OS file writes, 947800 OS fsyncs
         $results->{'innodb_file_reads'} = $row[0];
         $results->{'innodb_file_writes'} = $row[4];
         $results->{'innodb_file_fsyncs'} = $row[8];
      }
      elsif (index($line, 'Pending normal aio reads:') != -1 ) {
         # Pending normal aio reads: 0, aio writes: 0,
         $results->{'innodb_pending_normal_aio_reads'} = $row[4];
         $results->{'innodb_pending_normal_aio_writes'} = $row[7];
      }
      elsif (index($line, 'ibuf aio reads') != -1 ) {
         #  ibuf aio reads: 0, log i/o's: 0, sync i/o's: 0
         $results->{'innodb_pending_ibuf_aio_reads'} = $row[3];
         $results->{'innodb_pending_aio_log_ios'}    = $row[6];
         $results->{'innodb_pending_aio_sync_ios'}   = $row[9];
      }
      elsif ( index($line, 'Pending flushes (fsync)') != -1 ) {
         # Pending flushes (fsync) log: 0; buffer pool: 0
	 $row[4] =~ s/\;$//;
         $results->{'innodb_pending_log_flushes'}      = $row[4];
         $results->{'innodb_pending_buf_pool_flushes'} = $row[7];
      }

      # INSERT BUFFER AND ADAPTIVE HASH INDEX
      elsif (index($line, 'Ibuf for space 0: size ') != -1 ) {
         # Older InnoDB code seemed to be ready for an ibuf per tablespace.  It
         # had two lines in the output.  Newer has just one line, see below.
         # Ibuf for space 0: size 1, free list len 887, seg size 889, is not empty
         # Ibuf for space 0: size 1, free list len 887, seg size 889,
         $results->{'innodb_ibuf_used_cells'} = $row[5];
         $results->{'innodb_ibuf_free_cells'} = $row[9];
         $results->{'innodb_ibuf_cell_count'} = $row[12];
      }
      elsif (index($line, 'Ibuf: size ') != -1 ) {
         # Ibuf: size 1, free list len 4634, seg size 4636,
         $results->{'innodb_ibuf_used_cells'} = $row[2];
         $results->{'innodb_ibuf_free_cells'} = $row[6];
         $results->{'innodb_ibuf_cell_count'} = $row[9];
         if (index($line, 'merges')) {
            $results->{'innodb_ibuf_merges'} = $row[10];
         }
      }
      elsif (index($line, ', delete mark ') > 0 and index($prev_line, 'merged operations:') != -1 ) {
         # Output of show engine innodb status has changed in 5.5
         # merged operations:
         # insert 593983, delete mark 387006, delete 73092
         $results->{'innodb_ibuf_inserts'} = $row[1];
         $results->{'innodb_ibuf_merged'} = $row[1] + $row[4] + $row[6];
      }
      elsif (index($line, ' merged recs, ') > 0 ) {
         # 19817685 inserts, 19817684 merged recs, 3552620 merges
         $results->{'innodb_ibuf_inserts'} = $row[0];
         $results->{'innodb_ibuf_merged'} = $row[2];
         $results->{'innodb_ibuf_merges'} = $row[5];
      }
      elsif (index($line, 'Hash table size ') != -1 ) {
         # In some versions of InnoDB, the used cells is omitted.
         # Hash table size 4425293, used cells 4229064, ....
         # Hash table size 57374437, node heap has 72964 buffer(s) <-- no used cells
         $results->{'innodb_hash_index_cells_total'} = $row[3];
         $results->{'innodb_hash_index_cells_used'}
            = index($line, 'used cells') > 0 ? $row[6] : '0';
      }

      # LOG
      elsif (index($line, " log i/o's done, ") > 0 ) {
         # 3430041 log i/o's done, 17.44 log i/o's/second
         # 520835887 log i/o's done, 17.28 log i/o's/second, 518724686 syncs, 2980893 checkpoints
         # TODO: graph syncs and checkpoints
         $results->{'innodb_log_writes'} = $row[0];
      }
      elsif (index($line, " pending log writes, ") > 0 ) {
         # 0 pending log writes, 0 pending chkp writes
         $results->{'innodb_pending_log_writes'} = $row[0];
         $results->{'innodb_pending_chkp_writes'} = $row[4];
      }
      elsif (index($line, "Log sequence number") != -1 ) {
         # This number is NOT printed in hex in InnoDB plugin.
         # Log sequence number 13093949495856 //plugin
         # Log sequence number 125 3934414864 //normal
         $results->{'innodb_log_bytes_written'}
            = defined($row[4])
            ? make_bigint($row[3], $row[4])
            : $row[3];
      }
      elsif (index($line, "Log flushed up to") != -1 ) {
         # This number is NOT printed in hex in InnoDB plugin.
         # Log flushed up to   13093948219327
         # Log flushed up to   125 3934414864
         $results->{'innodb_log_bytes_flushed'}
            = defined($row[5])
            ? make_bigint($row[4], $row[5]) : $row[4];
      }
      elsif (index($line, "Last checkpoint at") != -1 ) {
         # Last checkpoint at  125 3934293461
         $results->{'innodb_last_checkpoint'}
            = defined($row[4])
            ? make_bigint($row[3], $row[4])
            : $row[3];
      }

      # BUFFER POOL AND MEMORY
      elsif (index($line, "Total memory allocated") != -1 && index($line, "in additional pool allocated") > 0 ) {
         # Total memory allocated 29642194944; in additional pool allocated 0
         # Total memory allocated by read views 96
	 $row[3] =~ s/\;$//;
         $results->{'innodb_total_mem_alloc'}       = $row[3];
         $results->{'innodb_additional_pool_alloc'} = $row[8];
      }
      elsif(index($line, 'Adaptive hash index ') != -1 ) {
         #   Adaptive hash index 1538240664 	(186998824 + 1351241840)
         $results->{'innodb_adaptive_hash_memory'} = $row[3];
      }
      elsif(index($line, 'Page hash           ') != -1 ) {
         #   Page hash           11688584
         $results->{'innodb_page_hash_memory'} = $row[2];
      }
      elsif(index($line, 'Dictionary cache    ') != -1 ) {
         #   Dictionary cache    145525560 	(140250984 + 5274576)
         $results->{'innodb_dictionary_cache_memory'} = $row[2];
      }
      elsif(index($line, 'File system         ') != -1 ) {
         #   File system         313848 	(82672 + 231176)
         $results->{'innodb_file_system_memory'} = $row[2];
      }
      elsif(index($line, 'Lock system         ') != -1 ) {
         #   Lock system         29232616 	(29219368 + 13248)
         $results->{'innodb_lock_system_memory'} = $row[2];
      }
      elsif(index($line, 'Recovery system     ') != -1 ) {
         #   Recovery system     0 	(0 + 0)
         $results->{'innodb_recovery_system_memory'} = $row[2];
      }
      elsif(index($line, 'Threads             ') != -1 ) {
         #   Threads             409336 	(406936 + 2400)
         $results->{'innodb_thread_hash_memory'} = $row[1];
      }
      elsif(index($line, 'innodb_io_pattern   ') != -1 ) {
         #   innodb_io_pattern   0 	(0 + 0)
         $results->{'innodb_io_pattern_memory'} = $row[1];
      }
      elsif (index($line, "Buffer pool size ") != -1 ) {
         # The " " after size is necessary to avoid matching the wrong line:
         # Buffer pool size        1769471
         # Buffer pool size, bytes 28991012864
         $results->{'innodb_pool_size'} = $row[3];
      }
      elsif (index($line, "Free buffers") != -1 ) {
         # Free buffers            0
         $results->{'innodb_free_pages'} = $row[2];
      }
      elsif (index($line, "Database pages") != -1 ) {
         # Database pages          1696503
         $results->{'innodb_database_pages'} = $row[2];
      }
      elsif (index($line, "Modified db pages") != -1 ) {
         # Modified db pages       160602
         $results->{'innodb_modified_pages'} = $row[3];
      }
      elsif (index($line, "Pages read ahead") != -1 ) {
         # Must do this BEFORE the next test, otherwise it'll get fooled by this
         # line from the new plugin (see samples/innodb-015.txt):
         # Pages read ahead 0.00/s, evicted without access 0.06/s
         # TODO: No-op for now, see issue 134.
      }
      elsif (index($line, "Pages read") != -1 ) {
         # Pages read 15240822, created 1770238, written 21705836
         $results->{'innodb_pages_read'}    = $row[2];
         $results->{'innodb_pages_created'} = $row[4];
         $results->{'innodb_pages_written'} = $row[6];
      }

      # ROW OPERATIONS
      elsif (index($line, 'Number of rows inserted') != -1 ) {
         # Number of rows inserted 50678311, updated 66425915, deleted 20605903, read 454561562
         $results->{'innodb_rows_inserted'} = $row[4];
         $results->{'innodb_rows_updated'} = $row[6];
         $results->{'innodb_rows_deleted'} = $row[8];
         $results->{'innodb_rows_read'}     = $row[10];
      }
      elsif (index($line, " queries inside InnoDB, ") > 0 ) {
         # 0 queries inside InnoDB, 0 queries in queue
         $results->{'innodb_queries_inside'} = $row[0];
         $results->{'innodb_queries_queued'} = $row[4];
      }

      $prev_line = $line;
   }

    foreach my $key ( ('innodb_spin_waits', 'innodb_spin_rounds', 'innodb_os_waits')) {
	my $tmp = 0;
	$tmp += $_ foreach @{$results->{$key}};
	$results->{$key} = $tmp;
    }

    $results->{'innodb_unflushed_log'} = $results->{'innodb_log_bytes_written'} - $results->{'innodb_log_bytes_flushed'};
    $results->{'innodb_uncheckpointed_bytes'} = $results->{'innodb_log_bytes_written'} - $results->{'innodb_last_checkpoint'};

    return $results;
}

sub make_bigint($$) {
    my $left = shift;
    my $right = shift;

    return sprintf("%d", hex($left)) unless defined $right;

    $left = defined($left) ? $left : '0';
    $right = defined($right) ? $right : '0';

    return $left + $right;
}

