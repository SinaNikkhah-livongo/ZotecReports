SET @start_dt = '%START_DT%';
SET @end_dt = '%END_DT%';

SELECT
    ConsultID
     ,PatientMRN
     ,PatientFullName
     ,PatientDOB
     ,DateOfService
     ,TimeOfService
     ,CASE WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_RENDERING' THEN TRIM(CONCAT(default_billing_provider_last_nm,", ",default_billing_provider_first_nm," ",default_billing_provider_middle_nm))   -- default_billing_provider_First_NM
           WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_CONSULT'   THEN TRIM(CONCAT(prvdr_person_last_nm,", ",prvdr_person_first_nm," ",prvdr_person_middle_nm)) -- DoctorFirstName
           ELSE TRIM(CONCAT(billing_provider_last_nm,", ",billing_provider_first_nm," ",billing_provider_middle_nm)) END RenderingProviderFullName
     ,AccessionID
     ,CASE WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_RENDERING' THEN default_billing_provider_npi
           WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_CONSULT'   THEN prvdr_person_npi
           ELSE billing_provider_npi END RenderingProviderNPI
     ,PatientSSN
     ,PayerCD
     ,ServiceSpecialty
     ,ConsultationState
     ,CASE
          WHEN ServiceSpecialty = 'INFO_VPC' THEN 'VPC'
          WHEN claim_billing_method_cd = 'CLAIMBILLINGMETHOD_FEEFORSERVICE' THEN 'FFS'
          WHEN ServiceSpecialty = 'VPC' THEN 'VPC'
          ELSE 'TELADOC' END AS Practice
FROM (
         SELECT
             c.consultation_id AS ConsultID
              ,m.member_id AS PatientMRN
              ,TRIM(CONCAT(UPPER(TRIM(IFNULL(p.last_nm,''))),", ",UPPER(TRIM(IFNULL(p.first_nm,''))),' ',UPPER(TRIM(IFNULL(p.middle_nm,''))))) AS PatientFullName
              ,DATE_FORMAT(p.dob,'%Y%m%d') AS patientDOB
              ,DATE_FORMAT(c.`actual_start_dt`,'%Y%m%d') AS DateOfService
              ,DATE_FORMAT(c.`actual_start_dt`,'%H:%i') AS TimeOfService
              ,c.state_cd AS ConsultationState
              ,payer_cd AS PayerCD
              ,CASE WHEN gs.consult_reimbursement_method_cd = 'CONSULTREIMBURSEMENT_INFOCLAIM'
                        THEN CONCAT('INFO_',(SELECT service_specialty_cd
                                             FROM group_service_specialty_relations
                                             WHERE group_service_specialty_relations.group_service_specialty_relation_id = c.group_service_specialty_relation_id
                                             LIMIT 1))
                    ELSE (SELECT service_specialty_cd
                          FROM group_service_specialty_relations
                          WHERE group_service_specialty_relations.group_service_specialty_relation_id = c.group_service_specialty_relation_id
                          LIMIT 1)
             END AS ServiceSpecialty
              ,(SELECT TRIM(UPPER(claim_billing_method_cd)) FROM group_service_specialty_claim_billing_method_relations gsscbr
                WHERE c.group_service_specialty_relation_id = gsscbr.group_service_specialty_relation_id
                  AND DATE(c.actual_start_dt) BETWEEN effective_start_dt AND COALESCE(effective_end_dt  ,'9999-12-31') -- the service date should be within the claim billing method effective dates
                  AND gsscbr.exclusion_cd = 'IN'
                ORDER BY group_service_specialty_claim_billing_method_relation_id DESC LIMIT 1) AS claim_billing_method_cd
              ,rendering_provider_cd
              ,(SELECT organization_id
                FROM teladoc_eds.billings b
                         JOIN teladoc_eds.group_billing_relations gbr ON gbr.billing_id = b.billing_id
                WHERE gbr.group_id = c.group_id
                  AND gbr.exclusion_cd = 'IN'
                  AND b.exclusion_cd = 'IN'
                LIMIT 1 ) AS AccessionID
              ,CASE WHEN p.ssn REGEXP '^[0-9]{9}$' THEN p.ssn ELSE '' END AS PatientSSN
              ,default_billing_provider.NPI default_billing_provider_npi
              ,UPPER(TRIM(IFNULL(default_billing_provider.First_NM,''))) AS default_billing_provider_first_nm
              ,UPPER(TRIM(IFNULL(default_billing_provider.Last_NM,''))) AS default_billing_provider_last_nm
              ,CAST('' AS CHAR(1)) AS default_billing_provider_middle_nm
              ,UPPER(TRIM(IFNULL(CASE WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_RENDERING' AND billing_provider_rendering.provider_id IS NOT NULL THEN billing_provider_rendering.NPI
                                      WHEN billing_provider.provider_id IS NULL THEN default_billing_provider.NPI
                                      ELSE billing_provider.NPI END,''))) AS billing_provider_npi
              ,UPPER(TRIM(IFNULL(CASE WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_RENDERING' AND  billing_provider_rendering.provider_id IS NOT NULL THEN billing_provider_rendering.First_NM
                                      WHEN billing_provider.provider_id IS NULL THEN default_billing_provider.First_NM
                                      ELSE billing_provider.First_NM END,''))) AS billing_provider_first_nm
              ,UPPER(TRIM(IFNULL(CASE WHEN rendering_provider_cd = 'CLAIMRENDERINGPROVIDER_RENDERING' AND billing_provider_rendering.provider_id IS NOT NULL THEN billing_provider_rendering.Last_NM
                                      WHEN billing_provider.provider_id IS NULL THEN default_billing_provider.Last_NM
                                      ELSE billing_provider.Last_NM END,''))) AS  billing_provider_last_nm
              ,CAST('' AS CHAR(1)) AS billing_provider_middle_nm
              ,(SELECT alt_id
                FROM alt_provider_ids
                WHERE provider_id = c.provider_id
                  AND issuing_body_cd = 'PROVIDERID_NPI'
                  AND (expiration_dt IS NULL)
                  AND exclusion_cd = 'IN'
                LIMIT 1
         ) AS prvdr_person_npi
              ,UPPER(TRIM(IFNULL(prvdr_person.first_nm,''))) AS prvdr_person_first_nm
              ,UPPER(TRIM(IFNULL(prvdr_person.last_nm,''))) AS prvdr_person_last_nm
              ,UPPER(TRIM(IFNULL(prvdr_person.middle_nm,''))) AS prvdr_person_middle_nm
         FROM
             teladoc_eds.consultations c
                 LEFT JOIN teladoc_eds.members m ON c.member_id = m.member_id AND m.exclusion_cd = 'IN'
                 LEFT JOIN teladoc_eds.persons p ON p.person_id =m.person_id AND p.exclusion_cd = 'IN'
                 LEFT JOIN providers prvdr ON prvdr.provider_id = c.provider_id
                 LEFT JOIN persons prvdr_person ON prvdr_person.person_id = prvdr.person_id
                 LEFT JOIN member_payer_service_specialty_relations mpssr ON mpssr.member_payer_service_specialty_relation_id = c.member_payer_service_specialty_relation_id
                 LEFT JOIN group_payer_service_specialty_relations gpssra
                           ON gpssra.group_payer_service_specialty_relation_id = mpssr.group_payer_service_specialty_relation_id
                               AND gpssra.exclusion_cd = 'IN'
                 LEFT JOIN (SELECT gpssrd.group_payer_service_specialty_relation_id, gpssrd.group_service_specialty_relation_id, payer_id, exclusion_cd
                            FROM group_payer_service_specialty_relations gpssrd
                            WHERE gpssrd.exclusion_cd = 'IN'
                              AND gpssrd.group_payer_service_specialty_relation_id = (SELECT group_payer_service_specialty_relation_id
                                                                                      FROM group_payer_service_specialty_relations gpssrc
                                                                                      WHERE gpssrc.exclusion_cd = 'IN'
                                                                                        AND gpssrc.group_service_specialty_relation_id = gpssrd.group_service_specialty_relation_id
                                                                                      ORDER BY gpssrc.updated_at DESC LIMIT 1)
             ) gpssrb
                           ON gpssrb.group_service_specialty_relation_id = c.group_service_specialty_relation_id AND gpssrb.exclusion_cd = 'IN'
                 LEFT JOIN payers ON payers.payer_id = COALESCE(gpssra.payer_id, gpssrb.payer_id)
                 LEFT JOIN teladoc_eds.group_settings gs ON c.group_id = gs.group_id AND gs.exclusion_cd = 'IN'
                 LEFT JOIN (SELECT cp.Provider_ID,
                                   rpr.Service_Specialty_Feature_CD,
                                   p.First_NM,
                                   p.Last_NM,
                                   (SELECT alt_id FROM alt_provider_ids
                                    WHERE provider_id = cp.provider_id
                                      AND issuing_body_cd = 'PROVIDERID_NPI'
                                      AND (expiration_dt IS NULL)
                                      AND exclusion_cd = 'IN'
                                    LIMIT 1
                                   ) NPI,
                                   p.SSN AS TIN,
                                   rib.State_CD,
                                   prr.Provider_Role_CD,
                                   pa.Address_Line1,
                                   pa.City,
                                   pa.State_Province,
                                   pa.Postal,
                                   rpr.claim_taxonomy_cd
                            FROM providers	cp
                                     INNER JOIN persons p
                                                ON p.Person_ID = cp.Person_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN parties pty
                                                ON pty.Party_ID = p.Party_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN provider_licenses pl
                                                ON pl.Provider_ID = cp.Provider_ID
                                     INNER JOIN ref_issuing_bodies rib ON rib.Issuing_Body_CD = pl.Issuing_Body_CD AND rib.Category_CD IN ('ISSUINGBODY_MEDICALLICENSE')
                                AND pl.Exclusion_CD = 'IN'
                                     INNER JOIN provider_role_relations prr
                                                ON prr.Provider_ID =	cp.ProvideR_ID
                                                    AND prr.Exclusion_CD = 'IN'
                                     INNER JOIN ref_provider_roles rpr
                                                ON rpr.Provider_Role_CD = prr.Provider_Role_CD
                                     INNER	JOIN party_addresses pa
                                                   ON pa.Party_ID = pty.Party_ID
                                                       AND pa.Exclusion_CD = 'IN'
                                                       AND pa.address_type_cd = 'ADDRESSTYPE_WORK'
                            WHERE cp.Exclusion_CD =	'IN'
                              AND cp.Provider_Type_CD = 'PROVIDERTYPE_CLAIM'
             ) billing_provider
                           ON
                               (payers.provider_role_tin_override_cd IS NOT NULL OR billing_provider.Service_Specialty_Feature_CD =
                                                                                    (SELECT CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD)
                                                                                     FROM invoice_items
                                                                                              JOIN invoices
                                                                                                   ON invoices.invoice_id	= invoice_items.invoice_id
                                                                                              JOIN ref_skus
                                                                                                   ON ref_skus.sku_cd = invoices.sku_cd
                                                                                     WHERE invoice_tracking_id = c.consultation_id
                                                                                       AND invoice_tracking_type = 'Consultation'
                                                                                     LIMIT	1
                                                                                    )
                                   )
                                   AND billing_provider.provider_role_cd = IFNULL((SELECT CASE WHEN payers.provider_role_tin_override_cd IS NOT NULL THEN  payers.provider_role_tin_override_cd
                                                                                               WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_MD' THEN 'PSYCHIATRIST'
                                                                                               WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_NONMD' THEN 'THERAPIST'
                                                                                               ELSE CAST(NULL	AS CHAR) END
                                                                                   FROM invoice_items
                                                                                            JOIN invoices
                                                                                                 ON invoices.invoice_id = invoice_items.invoice_id
                                                                                            JOIN ref_skus
                                                                                                 ON ref_skus.sku_cd = invoices.sku_cd
                                                                                   WHERE invoice_tracking_id = c.consultation_id
                                                                                     AND invoice_tracking_type = 'Consultation'
                                                                                   LIMIT 1),billing_provider.provider_role_cd
                                                                           )
                                   AND billing_provider.State_CD =	payers.billing_provider_state_cd
                 LEFT JOIN (SELECT cp.Provider_ID,
                                   rpr.Service_Specialty_Feature_CD,
                                   p.First_NM,
                                   p.Last_NM,
                                   (SELECT alt_id
                                    FROM alt_provider_ids
                                    WHERE provider_id = cp.provider_id
                                      AND issuing_body_cd = 'PROVIDERID_NPI'
                                      AND (expiration_dt IS NULL)
                                      AND exclusion_cd = 'IN'
                                    LIMIT 1
                                   ) NPI,
                                   p.SSN AS TIN,
                                   rib.State_CD,
                                   prr.Provider_Role_CD,
                                   pa.Address_Line1,
                                   pa.City,
                                   pa.State_Province,
                                   pa.Postal,
                                   rpr.claim_taxonomy_cd
                            FROM providers	cp
                                     INNER JOIN persons p
                                                ON p.Person_ID = cp.Person_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN parties pty
                                                ON pty.Party_ID = p.Party_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN provider_licenses pl
                                                ON pl.Provider_ID = cp.Provider_ID
                                                    AND pl.Exclusion_CD = 'IN'
                                     INNER JOIN ref_issuing_bodies rib ON rib.Issuing_Body_CD = pl.Issuing_Body_CD AND rib.Category_CD IN ('ISSUINGBODY_MEDICALLICENSE')
                                AND pl.Exclusion_CD = 'IN'
                                     INNER JOIN provider_role_relations prr
                                                ON prr.Provider_ID =	cp.ProvideR_ID
                                                    AND prr.Exclusion_CD = 'IN'
                                     INNER JOIN ref_provider_roles rpr
                                                ON rpr.Provider_Role_CD = prr.Provider_Role_CD
                                     INNER JOIN party_addresses pa
                                                ON pa.Party_ID = pty.Party_ID
                                                    AND pa.Exclusion_CD = 'IN'
                                                    AND pa.address_type_cd = 'ADDRESSTYPE_RENDERING'
                            WHERE cp.Exclusion_CD = 'IN'
                              AND cp.Provider_Type_CD = 'PROVIDERTYPE_CLAIM'
             ) billing_provider_rendering
                           ON billing_provider_rendering.Service_Specialty_Feature_CD = (SELECT CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD)
                                                                                         FROM invoice_items
                                                                                                  JOIN invoices
                                                                                                       ON invoices.invoice_id = invoice_items.invoice_id
                                                                                                  JOIN ref_skus
                                                                                                       ON ref_skus.sku_cd = invoices.sku_cd
                                                                                         WHERE invoice_tracking_id = c.consultation_id
                                                                                           AND invoice_tracking_type = 'Consultation'
                                                                                         LIMIT 1
                           )
                               AND billing_provider_rendering.provider_role_cd = IFNULL((SELECT CASE WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_MD' THEN 'PSYCHIATRIST'
                                                                                                     WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_NONMD' THEN 'THERAPIST'
                                                                                                     ELSE CAST(NULL AS CHAR) END
                                                                                         FROM invoice_items
                                                                                                  JOIN invoices
                                                                                                       ON invoices.invoice_id = invoice_items.invoice_id
                                                                                                  JOIN ref_skus
                                                                                                       ON ref_skus.sku_cd = invoices.sku_cd
                                                                                         WHERE invoice_tracking_id = c.consultation_id
                                                                                           AND invoice_tracking_type = 'Consultation'
                                                                                         LIMIT 1),billing_provider_rendering.provider_role_cd
                                                                                 )
                               AND billing_provider_rendering.State_CD	= payers.billing_provider_state_cd
                 LEFT JOIN (SELECT cp.Provider_ID,
                                   rpr.Service_Specialty_Feature_CD,
                                   p.First_NM,
                                   p.Last_NM,
                                   (SELECT alt_id
                                    FROM alt_provider_ids
                                    WHERE provider_id = cp.provider_id
                                      AND issuing_body_cd = 'PROVIDERID_NPI'
                                      AND (expiration_dt IS NULL)
                                      AND exclusion_cd = 'IN' LIMIT 1
                                   ) NPI,
                                   p.SSN AS TIN,
                                   rib.State_CD,
                                   prr.Provider_Role_CD,
                                   pa.Address_Line1,
                                   pa.City,
                                   pa.State_Province,
                                   pa.Postal,
                                   rpr.claim_taxonomy_cd
                            FROM providers cp
                                     INNER JOIN persons p
                                                ON p.Person_ID	= cp.Person_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN parties	pty
                                                ON pty.Party_ID	= p.Party_ID
                                                    AND p.Exclusion_CD = 'IN'
                                     INNER JOIN provider_licenses	pl
                                                ON pl.Provider_ID = cp.Provider_ID
                                                    AND pl.Exclusion_CD = 'IN'
                                     INNER JOIN ref_issuing_bodies rib ON rib.Issuing_Body_CD = pl.Issuing_Body_CD AND rib.Category_CD IN ('ISSUINGBODY_MEDICALLICENSE')
                                AND pl.Exclusion_CD = 'IN'
                                     INNER JOIN provider_role_relations	prr
                                                ON prr.Provider_ID = cp.ProvideR_ID
                                                    AND prr.Exclusion_CD = 'IN'
                                     INNER JOIN ref_provider_roles	rpr
                                                ON rpr.Provider_Role_CD	= prr.Provider_Role_CD
                                     INNER JOIN party_addresses pa
                                                ON pa.Party_ID	= pty.Party_ID
                                                    AND pa.Exclusion_CD='IN'
                                                    AND pa.address_type_cd	= 'ADDRESSTYPE_WORK'
                            WHERE cp.Exclusion_CD = 'IN'
                              AND cp.Provider_Type_CD = 'PROVIDERTYPE_CLAIM'
                              AND rib.State_CD = 'TX'
             ) default_billing_provider
                           ON (payers.provider_role_tin_override_cd IS NOT NULL OR default_billing_provider.Service_Specialty_Feature_CD =
                                                                                   (SELECT CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD)
                                                                                    FROM invoice_items
                                                                                             JOIN invoices
                                                                                                  ON invoices.invoice_id	= invoice_items.invoice_id
                                                                                             JOIN ref_skus
                                                                                                  ON ref_skus.sku_cd = invoices.sku_cd
                                                                                    WHERE invoice_tracking_id = c.consultation_id
                                                                                      AND invoice_tracking_type = 'Consultation'
                                                                                    LIMIT 1)
                                  )
                               AND default_billing_provider.provider_role_cd = IFNULL((SELECT CASE WHEN payers.provider_role_tin_override_cd IS NOT NULL THEN payers.provider_role_tin_override_cd
                                                                                                   WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_MD' THEN 'PSYCHIATRIST'
                                                                                                   WHEN CONCAT(ref_skus.service_specialty_cd,'_',PROVIDER_SKILL_CD) = 'BEHAVHEALTH_NONMD' THEN 'THERAPIST'
                                                                                                   ELSE CAST(NULL	AS CHAR) END
                                                                                       FROM invoice_items
                                                                                                JOIN invoices
                                                                                                     ON invoices.invoice_id = invoice_items.invoice_id
                                                                                                JOIN ref_skus
                                                                                                     ON ref_skus.sku_cd = invoices.sku_cd
                                                                                       WHERE invoice_tracking_id = c.consultation_id
                                                                                         AND invoice_tracking_type = 'Consultation'
                                                                                       LIMIT 1
                                                                                      ),default_billing_provider.provider_role_cd)

         WHERE gs.consult_reimbursement_method_cd IN ('CONSULTREIMBURSEMENT_CLAIM','CONSULTREIMBURSEMENT_INFOCLAIM') AND
             c.`state_machine_cd` = 'CONSULTSTATUS_COM' AND c.exclusion_cd = 'IN'
           AND c.actual_start_dt BETWEEN @start_dt AND @end_dt  -- this field needs to be changed to c.updated_at during implementation
     )v
ORDER BY ConsultID
LIMIT 1000000
;