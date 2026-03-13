-- Need to run this query on a daily basis by changin the start_dt & end_dt variables
SET @start_dt = '%START_DT%';
SET @end_dt = '%END_DT%';

-- Clean up the tmp table that holds any prior consults and invoices to process
Delete from staging.tmp_process_zotec_member_payments;

-- load the invoice and consult list data that needs to be processed for given lower and upper bounds.
INSERT INTO staging.tmp_process_zotec_member_payments (consultation_id,invoice_id,created_at,created_by,updated_at,updated_by)
SELECT DISTINCT c1.consultation_id,ii.invoice_id,NOW(),0,NOW(),0
FROM teladoc_eds.invoice_items ii
         JOIN teladoc_eds.consultations c1
              ON c1.consultation_id = ii.`invoice_tracking_id` AND ii.`invoice_tracking_type` = 'CONSULTATION' AND ii.exclusion_cd = 'IN' AND c1.exclusion_cd = 'IN'
         JOIN  teladoc_eds.invoice_payments ip USE INDEX(invoice_payment_ibfk_5) ON ip.invoice_id = ii.invoice_id AND ip.exclusion_cd = 'IN' AND ip.payment_status_cd = 'PAYMENTSTATUS_APPRVD'
         LEFT JOIN teladoc_eds.group_settings gs ON c1.group_id = gs.group_id AND gs.exclusion_cd = 'IN'
WHERE
    gs.consult_reimbursement_method_cd IN ('CONSULTREIMBURSEMENT_CLAIM','CONSULTREIMBURSEMENT_INFOCLAIM') AND  -- filter by info claim & claim configured consults
    ip.updated_at BETWEEN @start_dt AND @end_dt
  AND c1.state_machine_cd = 'CONSULTSTATUS_COM';

-- member payment extract for zotec
SELECT
    PatientFirstName
     ,PatientLastName
     ,PatientMRN
     ,PatientDOB
     ,PatientSSN
     ,CASE WHEN PatientPhone REGEXP '^[0-9]{10}$' THEN PatientPhone ELSE '' END AS PatientPhone
     ,TRIM(COALESCE(CASE WHEN home_address_line1 IS NOT NULL AND home_address_line1 <> '' THEN home_address_line1 ELSE mail_address_line1 END,'')) AS PatientAddress
     ,LEFT(TRIM(COALESCE(CASE WHEN home_address_line1 IS NOT NULL AND home_address_line1 <> '' THEN home_postal_code ELSE mail_postal_code END,'')),5) AS PatientZip
     ,TransactionCode
     ,TransactionDate
     ,Amount
     ,LocationID
     ,DOS
     ,DOSTo
     ,IsPaidInFull
     ,DiscountPercent
     ,DiscountTransactionCode
FROM (
         SELECT
             UPPER(TRIM(p.first_nm)) AS PatientFirstName
              ,UPPER(TRIM(p.last_nm)) AS PatientLastName
              ,m.member_id AS PatientMRN
              ,DATE_FORMAT(p.dob,'%Y%m%d') AS PatientDOB
              ,'' AS PatientSSN
              ,COALESCE(
                 (SELECT CONCAT(TRIM(ppf.area_code), TRIM(ppf.phone_number)) FROM teladoc_eds.party_phone_faxes ppf WHERE ppf.phone_fax_type_cd = 'PHONEFAXTYPE_CELL' AND ppf.exclusion_cd ='IN' AND
                     ppf.party_id = p.party_id
                  ORDER BY ppf.party_phone_fax_id DESC LIMIT 1),
                 (SELECT CONCAT(TRIM(ppf.area_code), TRIM(ppf.phone_number)) FROM teladoc_eds.party_phone_faxes ppf WHERE ppf.phone_fax_type_cd = 'PHONEFAXTYPE_HOME' AND ppf.exclusion_cd ='IN' AND
                     ppf.party_id = p.party_id
                  ORDER BY ppf.party_phone_fax_id DESC LIMIT 1),
                 (SELECT CONCAT(TRIM(ppf.area_code), TRIM(ppf.phone_number)) FROM teladoc_eds.party_phone_faxes ppf WHERE ppf.phone_fax_type_cd = 'PHONEFAXTYPE_WORK' AND ppf.exclusion_cd ='IN' AND
                     ppf.party_id = p.party_id
                  ORDER BY ppf.party_phone_fax_id DESC LIMIT 1)
               ) AS PatientPhone
              ,(SELECT UPPER(TRIM(pah.address_line1)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_HOME' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS home_address_line1
              ,(SELECT UPPER(TRIM(pah.address_line2)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_HOME' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS home_address_line2
              ,(SELECT UPPER(TRIM(pah.city)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_HOME' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS home_city_nm
              ,(SELECT UPPER(TRIM(pah.state_province)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_HOME' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS home_state_province_cd
              ,(SELECT UPPER(TRIM(pah.postal)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_HOME' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS home_postal_code
              ,(SELECT UPPER(TRIM(pah.address_line1)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_MAIL' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS mail_address_line1
              ,(SELECT UPPER(TRIM(pah.address_line2)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_MAIL' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS mail_address_line2
              ,(SELECT UPPER(TRIM(pah.city)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_MAIL' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS mail_city_nm
              ,(SELECT UPPER(TRIM(pah.state_province)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_MAIL' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS mail_state_province_cd
              ,(SELECT UPPER(TRIM(pah.postal)) FROM  teladoc_eds.party_addresses pah WHERE pah.party_id=p.party_id AND pah.address_type_cd = 'ADDRESSTYPE_MAIL' AND pah.exclusion_cd='IN' ORDER BY pah.party_address_id DESC LIMIT 1) AS mail_postal_code
              ,CASE WHEN mc_payment_status.master_cd IN ('ACH','PAYPAL') THEN 'CHE'
                    ELSE 'CRE' END  AS TransactionCode
              ,DATE_FORMAT(ip.invoice_payment_dt,'%Y%m%d') AS TransactionDate
              ,ip.`invoice_payment_amount` AS Amount
              ,'TDTOSPT' AS LocationId
              ,DATE_FORMAT(c.`actual_start_dt`,'%Y%m%d') AS DOS
              ,CAST('' AS CHAR(1)) AS DOSTo
              ,CAST('' AS CHAR(1)) AS IsPaidInFull
              ,CAST('' AS CHAR(1)) AS DiscountPercent
              ,CAST('' AS CHAR(1)) AS DiscountTransactionCode
         -- Below fields not needed - just from a data observation stand point
/*
,ip.invoice_payment_id
,ip.invoice_id
,c.state_machine_cd as ConsultStatus
,c.exported_flg
,gs.`consult_reimbursement_method_cd`
,ip.`invoice_payment_dt` as actual_transaction_dt
,c.`actual_start_dt` as actual_date_of_service
*/
         FROM teladoc_eds.consultations c
                  JOIN
              (
                  SELECT consultation_id,invoice_id,
                         (SELECT invoice_payment_id FROM teladoc_eds.invoice_payments WHERE invoice_id = t.invoice_id AND exclusion_cd = 'IN'
                                                                                        AND payment_status_cd = 'PAYMENTSTATUS_APPRVD'
                          ORDER BY invoice_payment_id DESC LIMIT 1) AS recent_approved_invoice_payment_id
                  FROM
                      staging.tmp_process_zotec_member_payments t
              )i
              ON c.consultation_id = i.consultation_id
                  JOIN teladoc_eds.invoice_payments ip ON ip.invoice_payment_id = i.recent_approved_invoice_payment_id AND ip.exclusion_cd = 'IN'
                  LEFT JOIN teladoc_eds.group_settings gs ON c.group_id = gs.group_id AND gs.exclusion_cd = 'IN'
                  LEFT JOIN teladoc_eds.members m ON m.member_id = c.member_id AND m.exclusion_cd = 'IN'
                  LEFT JOIN teladoc_eds.persons p ON m.person_id = p.person_id AND p.exclusion_cd = 'IN'
                  LEFT JOIN teladoc_eds.master_codes mc_payment_status ON mc_payment_status.master_group_cd = 'PAYMENTTYPE' AND mc_payment_status.master_code_cd = ip.payment_type_cd AND mc_payment_status.active_flg = 'Y'
         WHERE
             ip.`invoice_payment_amount` <> 0 AND -- removing zero dollar payments as Zotec can accept negative charge too
             ip.payment_status_cd = 'PAYMENTSTATUS_APPRVD'
     )mp
ORDER BY patientmrn,transactiondate,dos,amount
LIMIT 100000;



