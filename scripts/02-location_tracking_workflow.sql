--
-- Workflow steps for the Location Tracking Server
--

--
-- 1. Create a tracking set
--

-- Server output shows useful tracing information
set serveroutput on;

--
-- 1. Initialize the environment for a tracking service.
--
-- It creates a tracking set, specifically the tables and queues required for the location tracking server.
begin
    sdo_trkr.create_tracking_set(
        'TS1'
        , 1     -- number of queues to create to manage tracking messages
        , 1     -- number of queues to create to manage location messages
    );
end;
/

/*
    Creating required tables and indexes...
    Created required tables and indexes.
    Creating tracking set... tracking_example
    Creating queue tables...
    Creating tracker and process queue tables...
    Created tracker and process queue tables.
    Creating location queue tables...
    Created location queue tables.
    Creating notification queue table...
    Created notification queue table.
    Queue tables created.
    Creating tracker and process queues...
    Created tracker and proc queues.
    Creating location queues...
    Created location queues.
    Creating notification queue...
    Created notification queue.
    Tracking set created.
*/

--
-- 2. Show the tracking set tables that were created.
--

-- Check the tables and views just created
select table_name from user_tables where table_name like '%TRACKER%';
select view_name from user_views where view_name like '%TRACKER%';

-- Check the queues that have been created
select name,queue_table from user_queues order by 1;

-- Check the queue tables
select queue_table from user_queue_tables;

/*
    Data Structures for the Location Tracking Server

    The location tracking server requires the user to specify a tracking set name when the server is created. Based on this name, additional data structures are created.

    <TS1_NAME>_TRACKING_REGIONS (region_id NUMBER, geometry MDSYS.SDO_GEOMETRY) is a table containing the tracking region polygons defined in the tracking set <TS1_NAME>. Users must insert the polygons into this table after the server is created. All of the polygons must be geodetic (using SRID 8307) and two dimensional. The table has a primary key defined on the REGION_ID column.
    <TS1_NAME>_TRACKER (object_id NUMBER, region_id NUMBER, queue_no NUMBER, alert_when VARCHAR2(2)) is a table whose entries map the relationship between an object and a region in which the object is tracked. The table has a primary key defined on the OBJECT_ID and REGION_ID columns. This table is managed using the TRACKER_MSG type; users should not update this table directly.
    <TS1_NAME>_TRACKER_QUEUES(num_loc_queues NUMBER, num_trkr_queues NUMBER) is a table that holds queue information needed by the server. The server populates and maintains this table; users should never modify this table.
    <TS1_NAME>_TRACKER_LOG (message_level VARCHAR2(1), message VARCHAR2(512), ts TIMESTAMP WITH TIMEZONE) is a table containing log messages generated by the server. Message leve l‘I’ indicates an informational message, and message level ‘E’ indicates an error message. This table is not dropped when the tracking set is dropped. However, if a tracking set of the same name is then created, this table is truncated and reused by the new tracking set.
    <TS1_NAME>_NOTIFICATIONS (object_id NUMBER, region_id NUMBER, time TIMESTAMP, x NUMBER, y NUMBER, state VARCHAR2(8)) is an auxiliary table provided to users to store messages from the notifications queue. The layout of columns in this table match that of the NOTIFICATION_MSG type. The X and Y columns are the coordinate that prompted the notification for object_id in region_id at the time. The STATE column shows if the point INSIDE or OUTSIDE the region. For tracking types INSIDE and OUTSIDE this value never changes. For tracking type TRANSITION this column is the state of the object at the time it generated the notification.
    <TS1_NAME>_TRAJECTORY is an auxiliary table not currently used by the location tracking server.

    In addition to these tables, the location tracking server also creates a set of Advanced Queuing (AQ) objects for managing the location, tracking and notification messages. All of the queues have a prefix of <TS1_NAME>, for example. <TS1_NAME>_TRACKER_Q_1 and <TS1_NAME>_LOCATION_Q_1.

*/


-- Optional step to change SRID for Tracking Region table from default value 8307 to 4326
drop index ts1_geom_sidx;
delete from user_sdo_geom_metadata where table_name like '%TRACKING_REGIONS';
commit;

insert into user_sdo_geom_metadata (
    table_name,
    column_name,
    diminfo,
    srid
) values (
    'ts1_tracking_regions',
    'geometry',
    sdo_dim_array(
        sdo_dim_element('X', -180.0, 180.0, 0.5),
        sdo_dim_element('Y', -90.0, 90.0, 0.5)
    ),
    4326   -- EPSG SRID for WGS 84
);

commit;
create index ts1_geom_sidx on ts1_tracking_regions(geometry) indextype is mdsys.spatial_index_v2;


--
-- 3. Start the tracking set
--
exec sdo_trkr.start_tracking_set('TS1');

/*
    Starting tracking set ts
    Starting tracker and process queues...
    Started tracker and proc queues.
    Starting location queues...
    Started location queues.
    Starting notification queue...
    Started notification queue.
    Started job ts1_trkr_job_1
    Started job ts1_loc_job_1
    Started tracking set.
*/

--
-- 4. Optional: Show the queues used by the tracking set
--
select name
from user_queues
where name like 'TS1%'
order by name;

--
-- 5. Optional: Show the scheduler jobs used by the tracking set
--
select job_name, state
from user_scheduler_jobs
where job_name like'TS1%'
order by job_name;

--
-- 6. Insert regions (as polygons)
--

-- Optional: Truncate table first
truncate table ts1_tracking_regions;

-- Insert a polygon for region 1. This polygon must be geodetic (using SRID 4326/8307) and 2D.
-- The region can be a multi-polygon.
insert into ts1_tracking_regions
values (
  1,
  mdsys.sdo_geometry(
    2003,
    4326,
    null,
    sdo_elem_info_array(1, 1003, 1),
    sdo_ordinate_array(12,51, 14,51, 14,53, 12,53, 12,51)));

commit;

--
-- 7. Create two objects-region pairs, objects 1 and 2 to be tracked in region 1.
--
--   Object 1 sends notification messages to queue 1 when it is inside region 1.
--   Object 2 sends notification messages to queue 1 when it is outside region 1.
exec sdo_trkr.send_tracking_msg('TS1', mdsys.tracker_msg(1, 1, 'I'));
exec sdo_trkr.send_tracking_msg('TS1', mdsys.tracker_msg(2, 1, 'O'));


--
-- 8. Show the object-region pairs in the tracking set
--
select object_id, region_id, alert_when from ts1_tracker;


--
-- 9. Send location messages.
--

-- Object 1 moves from SW to NE, object 2 moves from S to N
begin
    sdo_trkr.send_location_msgs(
    'TS1',
    mdsys.location_msg_arr(
        mdsys.location_msg(1,CURRENT_TIMESTAMP(),  11.5,50.5),
        mdsys.location_msg(1,CURRENT_TIMESTAMP()+1,12.5,51.5),
        mdsys.location_msg(1,CURRENT_TIMESTAMP()+2,13.5,52.5),
        mdsys.location_msg(1,CURRENT_TIMESTAMP()+3,14.5,53.5),
        mdsys.location_msg(2,CURRENT_TIMESTAMP(),  13,50.5),
        mdsys.location_msg(2,CURRENT_TIMESTAMP()+1,13,51.5),
        mdsys.location_msg(2,CURRENT_TIMESTAMP()+2,13,52.5),
        mdsys.location_msg(2,CURRENT_TIMESTAMP()+3,13,53.5)
    )
);
end;
/


--
-- 10. Show that 8 notification messages were generated
--
select *
from user_queues
where name='TS1_NOTIFICATION_Q'
order by name;


--
-- 11. Dequeue the notification messages into the notifications table.
--
declare
  message mdsys.notification_msg;
begin
  loop
    sdo_trkr.get_notification_msg(
      tracking_set_name => 'TS1',
      message => message,
      deq_wait =>2);	-- wait at most 2 seconds for a message
    if (message is null) then
      exit;
    end if;
    insert into ts1_notifications (
      object_id, region_id, time, x, y, state)
      (select
        message.object_id,
        message.region_id,
        message.time,
        message.x,
        message.y,
        message.state
      from sys.dual);
  end loop;
end;
/


-- Query the object id, region id, (x, y) coordinate and the objects
-- relationship to the region sorted by the time that was sent with
-- the objects location message.
select object_id, region_id, x, y, state
from ts1_notifications
order by object_id, time;


--
-- 12. Optional: Disable the tracking server's object-region pairs
--
exec sdo_trkr.send_tracking_msg('TS1',mdsys.tracker_msg(1, 1, 'D'));
exec sdo_trkr.send_tracking_msg('TS1',mdsys.tracker_msg(2, 1, 'D'));


--
-- 13. Stop the tracking set.
--
-- This stops the tracking sets queues and its scheduler jobs. Running stop_tracking_set
-- does not delete the tables and queues used by the tracking server so start_tracking_set
-- can be rerun and all of the object and region data is still available.
-- This must be done before dropping a tracking set.
exec sdo_trkr.stop_tracking_set('TS1');


--
-- 14. Drop the tracking set.
--
-- This completely deletes the tracking sets queues and tables.
-- Once completed all traces of the tracking set are removed except for the log table
-- which is left intact for debugging purposes.
-- If another tracking set of the same name is created the log table is truncated.
exec sdo_trkr.drop_tracking_set('TS1');


-- 15. Optional: Remove location tracking log (history)
drop table ts1_tracker_log purge;