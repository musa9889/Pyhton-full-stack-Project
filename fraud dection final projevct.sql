-- drop everything first so we can re-run cleanly
DROP TABLE IF EXISTS ResolutionLog CASCADE;
DROP TABLE IF EXISTS InvestigationCase CASCADE;
DROP TABLE IF EXISTS FraudFlag CASCADE;
DROP TABLE IF EXISTS Transaction CASCADE;
DROP TABLE IF EXISTS Account CASCADE;
DROP TABLE IF EXISTS Users CASCADE;


CREATE TABLE Users (
    UserID SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Email VARCHAR(150) NOT NULL UNIQUE,
    PhoneNumber VARCHAR(20),
    AccountStatus VARCHAR(20) NOT NULL DEFAULT 'active'
                  CHECK (AccountStatus IN ('active', 'suspended', 'closed'))
);

-- one account per user,
CREATE TABLE Account (
    AccountID SERIAL PRIMARY KEY,
    UserID INT NOT NULL UNIQUE REFERENCES Users(UserID) ON DELETE CASCADE,
    AccountType VARCHAR(30) NOT NULL CHECK (AccountType IN ('savings', 'checking', 'credit', 'wallet')),
    Balance NUMERIC(15,2) NOT NULL DEFAULT 0.00 CHECK (Balance >= 0),
    CreatedDate DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE Transaction (
    TransactionID SERIAL PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES Account(AccountID) ON DELETE CASCADE,
    Amount NUMERIC(15,2) NOT NULL CHECK (Amount > 0),
    TransactionType VARCHAR(20) NOT NULL CHECK (TransactionType IN ('credit', 'debit', 'transfer')),
    Timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    Status VARCHAR(10) NOT NULL CHECK (Status IN ('completed', 'failed', 'flagged'))
);

-- only flagged transactions end up here, trigger handles the insert automatically
CREATE TABLE FraudFlag (
    FlagID SERIAL PRIMARY KEY,
    TransactionID INT NOT NULL UNIQUE REFERENCES Transaction(TransactionID) ON DELETE CASCADE,
    RiskScore SMALLINT NOT NULL CHECK (RiskScore BETWEEN 0 AND 100),
    FlagReason TEXT NOT NULL,
    FlagDate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE InvestigationCase (
    CaseID SERIAL PRIMARY KEY,
    FlagID INT NOT NULL REFERENCES FraudFlag(FlagID) ON DELETE CASCADE,
    AssignedTo VARCHAR(100) NOT NULL,
    CaseStatus VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (CaseStatus IN ('open', 'in_progress', 'closed')),
    OpenDate DATE NOT NULL DEFAULT CURRENT_DATE,
    CloseDate DATE
);

-- one resolution per case,
CREATE TABLE ResolutionLog (
    LogID SERIAL PRIMARY KEY,
    CaseID INT NOT NULL UNIQUE REFERENCES InvestigationCase(CaseID) ON DELETE CASCADE,
    ResolutionType VARCHAR(30) NOT NULL CHECK (ResolutionType IN ('confirmed_fraud', 'false_positive', 'escalated', 'no_action')),
    Notes TEXT,
    ResolvedDate DATE NOT NULL DEFAULT CURRENT_DATE
);


CREATE INDEX idx_txn_account ON Transaction(AccountID);
CREATE INDEX idx_txn_status ON Transaction(Status);
CREATE INDEX idx_txn_timestamp ON Transaction(Timestamp);
CREATE INDEX idx_flag_risk ON FraudFlag(RiskScore);
CREATE INDEX idx_case_status ON InvestigationCase(CaseStatus);


-- this trigger fires after every transaction insert
-- if status is completed it updates the balance, failed and flagged are left alone
CREATE OR REPLACE FUNCTION apply_transaction_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Status = 'completed' THEN
        IF NEW.TransactionType = 'credit' THEN
            UPDATE Account SET Balance = Balance + NEW.Amount
            WHERE AccountID = NEW.AccountID;

        ELSIF NEW.TransactionType = 'debit' THEN
            IF (SELECT Balance FROM Account WHERE AccountID = NEW.AccountID) < NEW.Amount THEN
                RAISE EXCEPTION 'Insufficient balance for transaction %', NEW.TransactionID;
            END IF;
            UPDATE Account SET Balance = Balance - NEW.Amount
            WHERE AccountID = NEW.AccountID;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_apply_balance
AFTER INSERT ON Transaction
FOR EACH ROW EXECUTE FUNCTION apply_transaction_balance();


-- this trigger auto-creates a FraudFlag row whenever a transaction is flagged
-- risk score and reason are derived from the transaction itself so we never have to insert manually
CREATE OR REPLACE FUNCTION auto_create_fraud_flag()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Status = 'flagged' THEN
        INSERT INTO FraudFlag (TransactionID, RiskScore, FlagReason)
        VALUES (
            NEW.TransactionID,
            CASE
                WHEN NEW.Amount > 50000 THEN 90
                WHEN NEW.Amount > 10000 THEN 70
                WHEN NEW.Amount > 5000 THEN 55
                ELSE 40
            END,
            CASE
                WHEN NEW.Amount > 50000 AND NEW.TransactionType = 'debit' THEN 'Unusually large debit, possible account takeover'
                WHEN NEW.Amount > 50000 AND NEW.TransactionType = 'credit' THEN 'Unusually large credit, possible money laundering'
                WHEN NEW.Amount > 10000 THEN 'High-value transaction exceeds normal threshold'
                WHEN NEW.TransactionType = 'transfer' THEN 'Suspicious transfer pattern detected'
                ELSE 'Transaction flagged for manual review'
            END
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_flag
AFTER INSERT ON Transaction
FOR EACH ROW EXECUTE FUNCTION auto_create_fraud_flag();


INSERT INTO Users (Name, Email, PhoneNumber, AccountStatus) VALUES
('Alice Johnson', 'alice.johnson@email.com', '03001111001', 'active'),
('Bob Smith', 'bob.smith@email.com', '03001111002', 'active'),
('Carol White', 'carol.white@email.com', '03001111003', 'active'),
('David Brown', 'david.brown@email.com', '03001111004', 'active'),
('Eva Martinez', 'eva.martinez@email.com', '03001111005', 'active'),
('Frank Wilson', 'frank.wilson@email.com', '03001111006', 'suspended'),
('Grace Lee', 'grace.lee@email.com', '03001111007', 'active'),
('Henry Taylor', 'henry.taylor@email.com', '03001111008', 'active'),
('Irene Anderson', 'irene.anderson@email.com', '03001111009', 'active'),
('Jack Thomas', 'jack.thomas@email.com', '03001111010', 'active'),
('Karen Jackson', 'karen.jackson@email.com', '03001111011', 'active'),
('Liam Harris', 'liam.harris@email.com', '03001111012', 'active'),
('Mona Clark', 'mona.clark@email.com', '03001111013', 'active'),
('Nathan Lewis', 'nathan.lewis@email.com', '03001111014', 'active'),
('Olivia Robinson', 'olivia.robinson@email.com', '03001111015', 'active'),
('Paul Walker', 'paul.walker@email.com', '03001111016', 'active'),
('Queenie Hall', 'queenie.hall@email.com', '03001111017', 'active'),
('Ryan Allen', 'ryan.allen@email.com', '03001111018', 'suspended'),
('Sara Young', 'sara.young@email.com', '03001111019', 'active'),
('Tom Hernandez', 'tom.hernandez@email.com', '03001111020', 'active'),
('Uma King', 'uma.king@email.com', '03001111021', 'active'),
('Victor Wright', 'victor.wright@email.com', '03001111022', 'active'),
('Wendy Lopez', 'wendy.lopez@email.com', '03001111023', 'active'),
('Xander Hill', 'xander.hill@email.com', '03001111024', 'active'),
('Yasmine Scott', 'yasmine.scott@email.com', '03001111025', 'active'),
('Zack Green', 'zack.green@email.com', '03001111026', 'active'),
('Aaron Adams', 'aaron.adams@email.com', '03001111027', 'active'),
('Bella Baker', 'bella.baker@email.com', '03001111028', 'active'),
('Carlos Gonzalez', 'carlos.gonzalez@email.com', '03001111029', 'active'),
('Diana Nelson', 'diana.nelson@email.com', '03001111030', 'active'),
('Ethan Carter', 'ethan.carter@email.com', '03001111031', 'active'),
('Fiona Mitchell', 'fiona.mitchell@email.com', '03001111032', 'active'),
('George Perez', 'george.perez@email.com', '03001111033', 'active'),
('Hannah Roberts', 'hannah.roberts@email.com', '03001111034', 'active'),
('Isaac Turner', 'isaac.turner@email.com', '03001111035', 'active'),
('Julia Phillips', 'julia.phillips@email.com', '03001111036', 'active'),
('Kevin Campbell', 'kevin.campbell@email.com', '03001111037', 'active'),
('Laura Parker', 'laura.parker@email.com', '03001111038', 'active'),
('Mike Evans', 'mike.evans@email.com', '03001111039', 'suspended'),
('Nancy Edwards', 'nancy.edwards@email.com', '03001111040', 'active'),
('Oscar Collins', 'oscar.collins@email.com', '03001111041', 'active'),
('Penny Stewart', 'penny.stewart@email.com', '03001111042', 'active'),
('Quinn Sanchez', 'quinn.sanchez@email.com', '03001111043', 'active'),
('Rachel Morris', 'rachel.morris@email.com', '03001111044', 'active'),
('Steve Rogers', 'steve.rogers@email.com', '03001111045', 'active'),
('Tina Reed', 'tina.reed@email.com', '03001111046', 'active'),
('Ulrich Cook', 'ulrich.cook@email.com', '03001111047', 'active'),
('Violet Morgan', 'violet.morgan@email.com', '03001111048', 'active'),
('Will Bell', 'will.bell@email.com', '03001111049', 'active'),
('Xena Murphy', 'xena.murphy@email.com', '03001111050', 'active'),
('Yusuf Bailey', 'yusuf.bailey@email.com', '03001111051', 'active'),
('Zara Rivera', 'zara.rivera@email.com', '03001111052', 'active'),
('Alan Cooper', 'alan.cooper@email.com', '03001111053', 'active'),
('Brenda Richardson', 'brenda.richardson@email.com', '03001111054', 'active'),
('Clint Cox', 'clint.cox@email.com', '03001111055', 'active'),
('Daisy Howard', 'daisy.howard@email.com', '03001111056', 'active'),
('Edwin Ward', 'edwin.ward@email.com', '03001111057', 'active'),
('Faye Torres', 'faye.torres@email.com', '03001111058', 'active'),
('Gus Peterson', 'gus.peterson@email.com', '03001111059', 'active'),
('Holly Gray', 'holly.gray@email.com', '03001111060', 'active'),
('Ian Ramirez', 'ian.ramirez@email.com', '03001111061', 'active'),
('Jane James', 'jane.james@email.com', '03001111062', 'active'),
('Kyle Watson', 'kyle.watson@email.com', '03001111063', 'active'),
('Lily Brooks', 'lily.brooks@email.com', '03001111064', 'active'),
('Max Kelly', 'max.kelly@email.com', '03001111065', 'active'),
('Nina Sanders', 'nina.sanders@email.com', '03001111066', 'active'),
('Owen Price', 'owen.price@email.com', '03001111067', 'active'),
('Patrice Bennett', 'patrice.bennett@email.com', '03001111068', 'active'),
('Quincy Wood', 'quincy.wood@email.com', '03001111069', 'active'),
('Rosa Barnes', 'rosa.barnes@email.com', '03001111070', 'active'),
('Sam Ross', 'sam.ross@email.com', '03001111071', 'active'),
('Tara Henderson', 'tara.henderson@email.com', '03001111072', 'active'),
('Ulrike Coleman', 'ulrike.coleman@email.com', '03001111073', 'active'),
('Vincent Jenkins', 'vincent.jenkins@email.com', '03001111074', 'active'),
('Wanda Perry', 'wanda.perry@email.com', '03001111075', 'active'),
('Xavier Powell', 'xavier.powell@email.com', '03001111076', 'active'),
('Yolanda Long', 'yolanda.long@email.com', '03001111077', 'active'),
('Zachary Patterson', 'zachary.patterson@email.com', '03001111078', 'active'),
('Amy Hughes', 'amy.hughes@email.com', '03001111079', 'active'),
('Brian Flores', 'brian.flores@email.com', '03001111080', 'active'),
('Cecilia Washington', 'cecilia.washington@email.com', '03001111081', 'active'),
('Derek Butler', 'derek.butler@email.com', '03001111082', 'active'),
('Elaine Simmons', 'elaine.simmons@email.com', '03001111083', 'active'),
('Floyd Foster', 'floyd.foster@email.com', '03001111084', 'active'),
('Georgia Gonzales', 'georgia.gonzales@email.com', '03001111085', 'active'),
('Howard Bryant', 'howard.bryant@email.com', '03001111086', 'active'),
('Ingrid Alexander', 'ingrid.alexander@email.com', '03001111087', 'active'),
('Jerome Russell', 'jerome.russell@email.com', '03001111088', 'active'),
('Kathleen Griffin', 'kathleen.griffin@email.com', '03001111089', 'active'),
('Leonard Diaz', 'leonard.diaz@email.com', '03001111090', 'active'),
('Marlene Hayes', 'marlene.hayes@email.com', '03001111091', 'active'),
('Norman Myers', 'norman.myers@email.com', '03001111092', 'active'),
('Ophelia Ford', 'ophelia.ford@email.com', '03001111093', 'active'),
('Preston Hamilton', 'preston.hamilton@email.com', '03001111094', 'active'),
('Queenie Graham', 'queenie.graham2@email.com', '03001111095', 'active'),
('Roland Sullivan', 'roland.sullivan@email.com', '03001111096', 'active'),
('Sylvia Wallace', 'sylvia.wallace@email.com', '03001111097', 'active'),
('Theodore West', 'theodore.west@email.com', '03001111098', 'active'),
('Ursula Cole', 'ursula.cole@email.com', '03001111099', 'active'),
('Vance Dixon', 'vance.dixon@email.com', '03001111100', 'active');


INSERT INTO Account (UserID, AccountType, Balance, CreatedDate)
SELECT
    u.UserID,
    (ARRAY['savings','checking','credit','wallet'])[ ((u.UserID - 1) % 4) + 1 ],
    ROUND((RANDOM() * 49000 + 1000)::NUMERIC, 2),
    CURRENT_DATE - ((RANDOM() * 730)::INT)
FROM Users u;


-- completed transactions, trigger will add/subtract from balance automatically
INSERT INTO Transaction (AccountID, Amount, TransactionType, Timestamp, Status) VALUES
(1, 1200.00, 'credit', NOW() - INTERVAL '10 days', 'completed'),
(1, 350.00, 'debit', NOW() - INTERVAL '8 days', 'completed'),
(2, 4500.00, 'credit', NOW() - INTERVAL '15 days', 'completed'),
(2, 800.00, 'debit', NOW() - INTERVAL '12 days', 'completed'),
(3, 2200.00, 'credit', NOW() - INTERVAL '5 days', 'completed'),
(4, 500.00, 'credit', NOW() - INTERVAL '20 days', 'completed'),
(4, 200.00, 'debit', NOW() - INTERVAL '18 days', 'completed'),
(5, 9000.00, 'credit', NOW() - INTERVAL '3 days', 'completed'),
(5, 1500.00, 'debit', NOW() - INTERVAL '2 days', 'completed'),
(6, 300.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(7, 6700.00, 'credit', NOW() - INTERVAL '11 days', 'completed'),
(7, 1200.00, 'debit', NOW() - INTERVAL '9 days', 'completed'),
(8, 750.00, 'credit', NOW() - INTERVAL '14 days', 'completed'),
(9, 3300.00, 'credit', NOW() - INTERVAL '6 days', 'completed'),
(9, 600.00, 'debit', NOW() - INTERVAL '4 days', 'completed'),
(10, 1800.00, 'credit', NOW() - INTERVAL '9 days', 'completed'),
(10, 450.00, 'debit', NOW() - INTERVAL '7 days', 'completed'),
(11, 2500.00, 'credit', NOW() - INTERVAL '13 days', 'completed'),
(12, 900.00, 'credit', NOW() - INTERVAL '16 days', 'completed'),
(13, 4100.00, 'credit', NOW() - INTERVAL '4 days', 'completed'),
(14, 620.00, 'debit', NOW() - INTERVAL '8 days', 'completed'),
(15, 3800.00, 'credit', NOW() - INTERVAL '2 days', 'completed'),
(16, 1100.00, 'credit', NOW() - INTERVAL '22 days', 'completed'),
(17, 280.00, 'debit', NOW() - INTERVAL '19 days', 'completed'),
(18, 5500.00, 'credit', NOW() - INTERVAL '1 day', 'completed'),
(19, 990.00, 'debit', NOW() - INTERVAL '5 days', 'completed'),
(20, 2700.00, 'credit', NOW() - INTERVAL '10 days', 'completed'),
(21, 1300.00, 'credit', NOW() - INTERVAL '3 days', 'completed'),
(22, 420.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(23, 8800.00, 'credit', NOW() - INTERVAL '12 days', 'completed'),
(24, 1650.00, 'debit', NOW() - INTERVAL '8 days', 'completed'),
(25, 770.00, 'credit', NOW() - INTERVAL '15 days', 'completed'),
(26, 3200.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(27, 510.00, 'debit', NOW() - INTERVAL '4 days', 'completed'),
(28, 2100.00, 'credit', NOW() - INTERVAL '9 days', 'completed'),
(29, 340.00, 'debit', NOW() - INTERVAL '11 days', 'completed'),
(30, 6300.00, 'credit', NOW() - INTERVAL '2 days', 'completed'),
(31, 1450.00, 'credit', NOW() - INTERVAL '5 days', 'completed'),
(32, 680.00, 'debit', NOW() - INTERVAL '13 days', 'completed'),
(33, 4900.00, 'credit', NOW() - INTERVAL '16 days', 'completed'),
(34, 1250.00, 'debit', NOW() - INTERVAL '3 days', 'completed'),
(35, 2950.00, 'credit', NOW() - INTERVAL '18 days', 'completed'),
(36, 830.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(37, 5100.00, 'credit', NOW() - INTERVAL '8 days', 'completed'),
(38, 1700.00, 'credit', NOW() - INTERVAL '14 days', 'completed'),
(39, 490.00, 'debit', NOW() - INTERVAL '7 days', 'completed'),
(40, 3600.00, 'credit', NOW() - INTERVAL '11 days', 'completed'),
(41, 1100.00, 'credit', NOW() - INTERVAL '4 days', 'completed'),
(42, 720.00, 'debit', NOW() - INTERVAL '9 days', 'completed'),
(43, 8200.00, 'credit', NOW() - INTERVAL '1 day', 'completed'),
(44, 360.00, 'debit', NOW() - INTERVAL '5 days', 'completed'),
(45, 2800.00, 'credit', NOW() - INTERVAL '17 days', 'completed'),
(46, 1350.00, 'credit', NOW() - INTERVAL '20 days', 'completed'),
(47, 580.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(48, 7400.00, 'credit', NOW() - INTERVAL '3 days', 'completed'),
(49, 1900.00, 'debit', NOW() - INTERVAL '12 days', 'completed'),
(50, 4200.00, 'credit', NOW() - INTERVAL '8 days', 'completed'),
(51, 650.00, 'credit', NOW() - INTERVAL '10 days', 'completed'),
(52, 2400.00, 'debit', NOW() - INTERVAL '15 days', 'completed'),
(53, 3100.00, 'credit', NOW() - INTERVAL '5 days', 'completed'),
(54, 870.00, 'debit', NOW() - INTERVAL '9 days', 'completed'),
(55, 5600.00, 'credit', NOW() - INTERVAL '2 days', 'completed'),
(56, 1250.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(57, 430.00, 'debit', NOW() - INTERVAL '11 days', 'completed'),
(58, 9100.00, 'credit', NOW() - INTERVAL '4 days', 'completed'),
(59, 2050.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(60, 3750.00, 'credit', NOW() - INTERVAL '13 days', 'completed'),
(61, 1600.00, 'credit', NOW() - INTERVAL '8 days', 'completed'),
(62, 540.00, 'debit', NOW() - INTERVAL '3 days', 'completed'),
(63, 7800.00, 'credit', NOW() - INTERVAL '10 days', 'completed'),
(64, 1400.00, 'debit', NOW() - INTERVAL '14 days', 'completed'),
(65, 910.00, 'credit', NOW() - INTERVAL '5 days', 'completed'),
(66, 4400.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(67, 760.00, 'debit', NOW() - INTERVAL '9 days', 'completed'),
(68, 2600.00, 'credit', NOW() - INTERVAL '12 days', 'completed'),
(69, 390.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(70, 6100.00, 'credit', NOW() - INTERVAL '2 days', 'completed'),
(71, 1050.00, 'credit', NOW() - INTERVAL '16 days', 'completed'),
(72, 820.00, 'debit', NOW() - INTERVAL '4 days', 'completed'),
(73, 3400.00, 'credit', NOW() - INTERVAL '8 days', 'completed'),
(74, 1750.00, 'debit', NOW() - INTERVAL '11 days', 'completed'),
(75, 680.00, 'credit', NOW() - INTERVAL '3 days', 'completed'),
(76, 5300.00, 'credit', NOW() - INTERVAL '15 days', 'completed'),
(77, 940.00, 'debit', NOW() - INTERVAL '7 days', 'completed'),
(78, 2200.00, 'credit', NOW() - INTERVAL '10 days', 'completed'),
(79, 470.00, 'debit', NOW() - INTERVAL '5 days', 'completed'),
(80, 4800.00, 'credit', NOW() - INTERVAL '9 days', 'completed'),
(81, 1500.00, 'credit', NOW() - INTERVAL '6 days', 'completed'),
(82, 610.00, 'debit', NOW() - INTERVAL '3 days', 'completed'),
(83, 7200.00, 'credit', NOW() - INTERVAL '12 days', 'completed'),
(84, 1300.00, 'debit', NOW() - INTERVAL '8 days', 'completed'),
(85, 850.00, 'credit', NOW() - INTERVAL '4 days', 'completed'),
(86, 3900.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(87, 730.00, 'debit', NOW() - INTERVAL '10 days', 'completed'),
(88, 2900.00, 'credit', NOW() - INTERVAL '2 days', 'completed'),
(89, 560.00, 'debit', NOW() - INTERVAL '5 days', 'completed'),
(90, 5700.00, 'credit', NOW() - INTERVAL '11 days', 'completed'),
(91, 1150.00, 'credit', NOW() - INTERVAL '9 days', 'completed'),
(92, 780.00, 'debit', NOW() - INTERVAL '6 days', 'completed'),
(93, 4600.00, 'credit', NOW() - INTERVAL '3 days', 'completed'),
(94, 1850.00, 'debit', NOW() - INTERVAL '14 days', 'completed'),
(95, 920.00, 'credit', NOW() - INTERVAL '7 days', 'completed'),
(96, 3300.00, 'credit', NOW() - INTERVAL '5 days', 'completed'),
(97, 640.00, 'debit', NOW() - INTERVAL '8 days', 'completed'),
(98, 8600.00, 'credit', NOW() - INTERVAL '1 day', 'completed'),
(99, 2100.00, 'debit', NOW() - INTERVAL '4 days', 'completed'),
(100,4700.00, 'credit', NOW() - INTERVAL '6 days', 'completed');

-- failed transactions, these are recorded but trigger ignores them so no balance change
INSERT INTO Transaction (AccountID, Amount, TransactionType, Timestamp, Status) VALUES
(1, 5000.00, 'debit', NOW() - INTERVAL '6 days', 'failed'),
(3, 800.00, 'debit', NOW() - INTERVAL '3 days', 'failed'),
(7, 2200.00, 'debit', NOW() - INTERVAL '10 days', 'failed'),
(10, 3100.00, 'debit', NOW() - INTERVAL '5 days', 'failed'),
(15, 1500.00, 'credit', NOW() - INTERVAL '8 days', 'failed'),
(20, 7000.00, 'debit', NOW() - INTERVAL '2 days', 'failed'),
(25, 400.00, 'debit', NOW() - INTERVAL '7 days', 'failed'),
(30, 9500.00, 'credit', NOW() - INTERVAL '4 days', 'failed'),
(50, 1200.00, 'debit', NOW() - INTERVAL '9 days', 'failed'),
(75, 6600.00, 'debit', NOW() - INTERVAL '1 day', 'failed');

-- flagged transactions, FraudFlag rows are created automatically by the trigger
INSERT INTO Transaction (AccountID, Amount, TransactionType, Timestamp, Status) VALUES
(2, 75000.00, 'debit', NOW() - INTERVAL '5 days', 'flagged'),
(5, 55000.00, 'credit', NOW() - INTERVAL '3 days', 'flagged'),
(8, 12500.00, 'debit', NOW() - INTERVAL '7 days', 'flagged'),
(11, 62000.00, 'credit', NOW() - INTERVAL '2 days', 'flagged'),
(14, 8000.00, 'debit', NOW() - INTERVAL '10 days', 'flagged'),
(18, 95000.00, 'credit', NOW() - INTERVAL '1 day', 'flagged'),
(22, 15000.00, 'debit', NOW() - INTERVAL '4 days', 'flagged'),
(35, 48000.00, 'credit', NOW() - INTERVAL '6 days', 'flagged'),
(50, 7500.00, 'debit', NOW() - INTERVAL '8 days', 'flagged'),
(63, 83000.00, 'credit', NOW() - INTERVAL '3 days', 'flagged'),
(71, 23000.00, 'debit', NOW() - INTERVAL '9 days', 'flagged'),
(85, 11000.00, 'credit', NOW() - INTERVAL '5 days', 'flagged'),
(92, 67000.00, 'debit', NOW() - INTERVAL '2 days', 'flagged'),
(99, 6200.00, 'credit', NOW() - INTERVAL '4 days', 'flagged'),
(44, 42000.00, 'debit', NOW() - INTERVAL '7 days', 'flagged');


INSERT INTO InvestigationCase (FlagID, AssignedTo, CaseStatus, OpenDate, CloseDate) VALUES
(1, 'Analyst Tariq Hussain', 'closed', CURRENT_DATE - 4, CURRENT_DATE - 2),
(1, 'Analyst Zara Malik', 'closed', CURRENT_DATE - 2, CURRENT_DATE - 1),
(2, 'Analyst Bilal Ahmed', 'in_progress', CURRENT_DATE - 2, NULL),
(3, 'Analyst Sana Qureshi', 'closed', CURRENT_DATE - 6, CURRENT_DATE - 4),
(3, 'Analyst Omar Farooq', 'closed', CURRENT_DATE - 4, CURRENT_DATE - 2),
(4, 'Analyst Aisha Raza', 'open', CURRENT_DATE - 1, NULL),
(5, 'Analyst Usman Riaz', 'closed', CURRENT_DATE - 9, CURRENT_DATE - 7),
(5, 'Analyst Mariam Iqbal', 'closed', CURRENT_DATE - 7, CURRENT_DATE - 5),
(5, 'Analyst Hamza Sheikh', 'closed', CURRENT_DATE - 5, CURRENT_DATE - 3),
(6, 'Analyst Nadia Chaudhry', 'open', CURRENT_DATE, NULL),
(7, 'Analyst Ali Baig', 'closed', CURRENT_DATE - 3, CURRENT_DATE - 1),
(7, 'Analyst Sara Javed', 'in_progress', CURRENT_DATE - 1, NULL),
(8, 'Analyst Khalid Ansari', 'closed', CURRENT_DATE - 5, CURRENT_DATE - 3),
(9, 'Analyst Fatima Aziz', 'closed', CURRENT_DATE - 7, CURRENT_DATE - 5),
(9, 'Analyst Rahim Siddiqui', 'closed', CURRENT_DATE - 5, CURRENT_DATE - 3),
(10, 'Analyst Yusra Khan', 'in_progress', CURRENT_DATE - 2, NULL),
(11, 'Analyst Saad Mirza', 'closed', CURRENT_DATE - 8, CURRENT_DATE - 6),
(12, 'Analyst Hina Baig', 'closed', CURRENT_DATE - 4, CURRENT_DATE - 2),
(13, 'Analyst Faisal Rehman', 'open', CURRENT_DATE, NULL),
(14, 'Analyst Amna Shahid', 'closed', CURRENT_DATE - 3, CURRENT_DATE - 1),
(15, 'Analyst Junaid Hassan', 'closed', CURRENT_DATE - 6, CURRENT_DATE - 4),
(15, 'Analyst Maryam Anwar', 'in_progress', CURRENT_DATE - 2, NULL);


INSERT INTO ResolutionLog (CaseID, ResolutionType, Notes, ResolvedDate) VALUES
(1, 'confirmed_fraud', 'Card details stolen, transaction blocked and card reissued.', CURRENT_DATE - 2),
(2, 'false_positive', 'Transaction verified with customer via OTP, cleared.', CURRENT_DATE - 1),
(4, 'confirmed_fraud', 'Identity theft confirmed, account frozen and reported to FIA.', CURRENT_DATE - 4),
(5, 'no_action', 'Duplicate case, merged with CaseID 4.', CURRENT_DATE - 2),
(7, 'escalated', 'Escalated to law enforcement due to repeat pattern.', CURRENT_DATE - 7),
(8, 'confirmed_fraud', 'Fraudulent wire transfer, funds partially recovered.', CURRENT_DATE - 5),
(9, 'no_action', 'All remaining claims resolved in prior cases.', CURRENT_DATE - 3),
(11, 'false_positive', 'Business account, large transfer was pre-authorized.', CURRENT_DATE - 1),
(13, 'confirmed_fraud', 'Phishing attack, customer credentials compromised.', CURRENT_DATE - 3),
(14, 'confirmed_fraud', 'Mule account identified, law enforcement notified.', CURRENT_DATE - 5),
(15, 'no_action', 'Secondary review found no additional liability.', CURRENT_DATE - 3),
(17, 'false_positive', 'Large salary credit confirmed with employer.', CURRENT_DATE - 6),
(18, 'confirmed_fraud', 'Stolen debit card used, chargeback processed.', CURRENT_DATE - 2),
(20, 'escalated', 'Cross-border fraud pattern, referred to Interpol liaison.', CURRENT_DATE - 1),
(21, 'confirmed_fraud', 'Synthetic identity fraud, account closed.', CURRENT_DATE - 4);


-- all flagged transactions with risk info
SELECT
    t.TransactionID,
    u.Name AS CustomerName,
    a.AccountType,
    t.Amount,
    t.TransactionType,
    t.Timestamp,
    f.RiskScore,
    f.FlagReason,
    f.FlagDate
FROM Transaction t
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
JOIN FraudFlag f ON t.TransactionID = f.TransactionID
ORDER BY f.RiskScore DESC;


-- users with risk score 70 or above
SELECT
    u.UserID,
    u.Name,
    u.Email,
    u.AccountStatus,
    f.RiskScore,
    f.FlagReason
FROM FraudFlag f
JOIN Transaction t ON f.TransactionID = t.TransactionID
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
WHERE f.RiskScore >= 70
ORDER BY f.RiskScore DESC;


-- full pipeline from transaction all the way to resolution
SELECT
    u.Name AS Customer,
    t.Amount,
    t.TransactionType,
    f.RiskScore,
    ic.CaseID,
    ic.AssignedTo,
    ic.CaseStatus,
    ic.OpenDate,
    ic.CloseDate,
    rl.ResolutionType,
    rl.Notes AS ResolutionNotes
FROM Transaction t
JOIN FraudFlag f ON t.TransactionID = f.TransactionID
JOIN InvestigationCase ic ON f.FlagID = ic.FlagID
LEFT JOIN ResolutionLog rl ON ic.CaseID = rl.CaseID
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
ORDER BY ic.CaseID;


-- cases still open or in progress
SELECT
    ic.CaseID,
    u.Name AS Customer,
    t.Amount,
    f.RiskScore,
    ic.AssignedTo,
    ic.CaseStatus,
    ic.OpenDate
FROM InvestigationCase ic
JOIN FraudFlag f ON ic.FlagID = f.FlagID
JOIN Transaction t ON f.TransactionID = t.TransactionID
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
WHERE ic.CaseStatus IN ('open', 'in_progress')
ORDER BY ic.OpenDate;


-- count and totals grouped by transaction status
SELECT
    Status,
    COUNT(*) AS TotalCount,
    SUM(Amount) AS TotalAmount,
    ROUND(AVG(Amount), 2) AS AvgAmount
FROM Transaction
GROUP BY Status
ORDER BY Status;


-- only confirmed fraud resolutions
SELECT
    u.Name AS Customer,
    t.Amount,
    t.TransactionType,
    f.RiskScore,
    rl.ResolutionType,
    rl.Notes,
    rl.ResolvedDate
FROM ResolutionLog rl
JOIN InvestigationCase ic ON rl.CaseID = ic.CaseID
JOIN FraudFlag f ON ic.FlagID = f.FlagID
JOIN Transaction t ON f.TransactionID = t.TransactionID
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
WHERE rl.ResolutionType = 'confirmed_fraud'
ORDER BY rl.ResolvedDate DESC;


-- top 20 accounts by current balance
SELECT
    u.Name,
    a.AccountType,
    a.Balance AS CurrentBalance
FROM Account a
JOIN Users u ON a.UserID = u.UserID
ORDER BY a.Balance DESC
LIMIT 20;


-- flags that have more than one investigation opened on them
SELECT
    f.FlagID,
    u.Name AS Customer,
    t.Amount,
    f.RiskScore,
    COUNT(ic.CaseID) AS NumInvestigations
FROM FraudFlag f
JOIN Transaction t ON f.TransactionID = t.TransactionID
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
JOIN InvestigationCase ic ON f.FlagID = ic.FlagID
GROUP BY f.FlagID, u.Name, t.Amount, f.RiskScore
HAVING COUNT(ic.CaseID) > 1
ORDER BY NumInvestigations DESC;


-- failed transactions for record
SELECT
    t.TransactionID,
    u.Name,
    t.Amount,
    t.TransactionType,
    t.Timestamp
FROM Transaction t
JOIN Account a ON t.AccountID = a.AccountID
JOIN Users u ON a.UserID = u.UserID
WHERE t.Status = 'failed'
ORDER BY t.Timestamp DESC;


-- daily summary of flagged transactions over the last 30 days
SELECT
    DATE(t.Timestamp) AS TxnDate,
    COUNT(*) AS FlaggedCount,
    SUM(t.Amount) AS TotalFlaggedAmount,
    MAX(f.RiskScore) AS MaxRiskScore
FROM Transaction t
JOIN FraudFlag f ON t.TransactionID = f.TransactionID
WHERE t.Timestamp >= NOW() - INTERVAL '30 days'
GROUP BY DATE(t.Timestamp)
ORDER BY TxnDate DESC;