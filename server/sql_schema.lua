---@diagnostic disable: undefined-global
local function checkTable(tableName, createSql, nextStep)
    MySQL.scalar("SHOW TABLES LIKE ?", { tableName }, function(exists)
        if exists then
            if nextStep then nextStep() end
            return
        end

        MySQL.query(createSql, {}, function()
            print(("[dvr_power] ✓ Table %s créée"):format(tableName))
            if nextStep then nextStep() end
        end)
    end)
end

local function checkColumn(tableName, columnName, alterSql, nextStep)
    MySQL.scalar([[
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName }, function(col)
        if col then
            if nextStep then nextStep() end
            return
        end

        MySQL.query(alterSql, {}, function()
            print(("[dvr_power] ✓ Colonne %s.%s ajoutée"):format(tableName, columnName))
            if nextStep then nextStep() end
        end)
    end)
end

local function ensureCharacterMagicHp(nextStep)
    checkTable("character_magic_hp", [[
        CREATE TABLE IF NOT EXISTS `character_magic_hp` (
            `identifier` VARCHAR(60) NOT NULL PRIMARY KEY,
            `current_hp` INT NOT NULL DEFAULT 100,
            `max_hp` INT NOT NULL DEFAULT 100,
            `is_dead` TINYINT(1) NOT NULL DEFAULT 0,
            `last_damage_time` DATETIME NULL,
            `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], function()
        checkColumn("character_magic_hp", "current_hp", "ALTER TABLE `character_magic_hp` ADD COLUMN `current_hp` INT NOT NULL DEFAULT 100", function()
        checkColumn("character_magic_hp", "max_hp", "ALTER TABLE `character_magic_hp` ADD COLUMN `max_hp` INT NOT NULL DEFAULT 100", function()
        checkColumn("character_magic_hp", "is_dead", "ALTER TABLE `character_magic_hp` ADD COLUMN `is_dead` TINYINT(1) NOT NULL DEFAULT 0", function()
        checkColumn("character_magic_hp", "last_damage_time", "ALTER TABLE `character_magic_hp` ADD COLUMN `last_damage_time` DATETIME NULL", function()
        checkColumn("character_magic_hp", "updated_at", "ALTER TABLE `character_magic_hp` ADD COLUMN `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP", function()
            if nextStep then nextStep() end
        end) end) end) end) end)
    end)
end

local function ensureCharacterSpells(nextStep)
    checkTable("character_spells", [[
        CREATE TABLE IF NOT EXISTS `character_spells` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `spell_id` VARCHAR(60) NOT NULL,
            `level` INT NOT NULL DEFAULT 0,
            `unlocked_at` DATETIME NULL,
            KEY `idx_identifier` (`identifier`),
            KEY `idx_spell` (`spell_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], function()
        checkColumn("character_spells", "identifier", "ALTER TABLE `character_spells` ADD COLUMN `identifier` VARCHAR(60) NOT NULL", function()
        checkColumn("character_spells", "spell_id", "ALTER TABLE `character_spells` ADD COLUMN `spell_id` VARCHAR(60) NOT NULL", function()
        checkColumn("character_spells", "level", "ALTER TABLE `character_spells` ADD COLUMN `level` INT NOT NULL DEFAULT 0", function()
        checkColumn("character_spells", "unlocked_at", "ALTER TABLE `character_spells` ADD COLUMN `unlocked_at` DATETIME NULL", function()
            if nextStep then nextStep() end
        end) end) end) end)
    end)
end

local function ensureProfessorData(nextStep)
    checkTable("professor_data", [[
        CREATE TABLE IF NOT EXISTS `professor_data` (
            `id` INT NOT NULL PRIMARY KEY,
            `classes` LONGTEXT NULL,
            `notes` LONGTEXT NULL,
            `attendance` LONGTEXT NULL,
            `history` LONGTEXT NULL,
            `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], function()
        checkColumn("professor_data", "classes", "ALTER TABLE `professor_data` ADD COLUMN `classes` LONGTEXT NULL", function()
        checkColumn("professor_data", "notes", "ALTER TABLE `professor_data` ADD COLUMN `notes` LONGTEXT NULL", function()
        checkColumn("professor_data", "attendance", "ALTER TABLE `professor_data` ADD COLUMN `attendance` LONGTEXT NULL", function()
        checkColumn("professor_data", "history", "ALTER TABLE `professor_data` ADD COLUMN `history` LONGTEXT NULL", function()
        checkColumn("professor_data", "updated_at", "ALTER TABLE `professor_data` ADD COLUMN `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP", function()
            if nextStep then nextStep() end
        end) end) end) end) end)
    end)
end

local function runSchemaChecks()
    ensureCharacterMagicHp(function()
    ensureCharacterSpells(function()
    ensureProfessorData(function()
        print('[dvr_power] ✓ Schéma base vérifié')
    end) end) end)
end

return runSchemaChecks
