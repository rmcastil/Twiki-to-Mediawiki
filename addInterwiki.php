<?php
/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 * http://www.gnu.org/copyleft/gpl.html
 *
 * USAGE: php addInterwiki.php [--overwrite] Prefix URL
 *
 * @file
 */

require_once __DIR__ . '/Maintenance.php';

/**
 *
 * Maintenance script to add Interwiki links
 *
 * @since 1.28
 */
class AddInterwiki extends LoggedUpdateMaintenance {
	public function __construct() {
		parent::__construct();
		$this->addDescription( 'Add an entry to the interwiki database table' );
		$this->addOption( 'overwrite', 'Overwrite existing links' );
		$this->addArg( 'prefix', 'Prefix', false );
		$this->addArg( 'URL', 'URL', false );
	}

	protected function getUpdateKey() {
		return __CLASS__;
	}

	protected function updateSkippedMessage() {
		return 'RFC and PMID already added to interwiki database table';
	}

	protected function doDBUpdates() {
		$interwikiCache = $this->getConfig()->get( 'InterwikiCache' );
		// Using something other than the database,
		if ( $interwikiCache !== false ) {
			return true;
		}

		$overwrite = $this->hasOption( 'overwrite' );

        if (!$this->hasArg(0)) { $this->error("Need to specify Prefix and URL", 1); }
        $prefix = $this->getArg(0);

        if (!$this->hasArg(1)) { $this->error("Need to specify URL", 1); }
        $url = $this->getArg(1);
	
        $dbw = $this->getDB( DB_MASTER );
        $dbw->replace(
            'interwiki',
            [ 'iw_prefix' ],
            [
                'iw_prefix' => $prefix,
                'iw_url' => $url,
                'iw_api' => '',
                'iw_wikiid' => '',
                'iw_local' => 0,
            ],
            __METHOD__,
            ($overwrite ? [] : [ 'IGNORE' ])
        );

		return true;
	}
}

$maintClass = 'AddInterwiki';
require_once RUN_MAINTENANCE_IF_MAIN;
